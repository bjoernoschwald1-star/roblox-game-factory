--!strict
-- Economy-Simulator: spielt einen idealisierten Spieler ohne Kaeufe (keine Products, keine Passes) ereignisbasiert
-- und deterministisch durch und meldet, nach wie vielen Minuten erstes Verkaufen, erstes Upgrade und jede Zone
-- erreicht werden. Die Grenzminuten (Fair-Play-Regel) sind Parameter von check, keine Konstanten im Core.
--
-- Modell und Annahmen:
-- - Gesammelt wird in der freigeschalteten Zone mit der hoechsten order (mit density > 0).
-- - Sammelrate pro Sekunde = min(density / respawnSeconds, rateLimit.maxItems / rateLimit.windowSeconds).
-- - Eine Fahrt fuellt das Inventar bis zur Kapazitaet und kostet zusaetzlich sim.tripSeconds; jeder Verkauf
--   sim.sellSeconds. Erloes = floor(Kapazitaet * gewichteter Durchschnittspreis der Zone * sellFactor).
-- - range beeinflusst die Rate im Modell nicht (der Spieler steht immer nah genug an den Items).
-- - Nach jedem Verkauf: zuerst die naechste Zone freischalten, wenn moeglich (coinsAtLeast, purchase,
--   upgradeLevel wie im Spiel), sonst das guenstigste kaufbare Upgrade (buyPolicy "cheapest_first");
--   wiederholen, solange etwas moeglich ist.
-- - range, capacity und sellFactor wie im Spiel: (base + Summe add) * Produkt mul der aktuellen Stufen.
-- - Der Lauf endet, wenn alle Zonen erreicht sind, maxMinutes erreicht ist oder kein Fortschritt moeglich ist.
local Schema = require(script.Parent.Schema)
local Validator = require(script.Parent.Validator)

export type Options = {
	maxMinutes: number,
	buyPolicy: string, -- "cheapest_first"
}

export type TimelineEntry = {
	minute: number,
	event: string,
}

export type Report = {
	minutesToFirstSell: number?,
	minutesToFirstUpgrade: number?,
	minutesToZone: { [number]: number? },
	reachedAllZones: boolean,
	coinsAtEnd: number,
	upgradeLevels: { [string]: number },
	timeline: { TimelineEntry },
}

export type Limits = {
	firstUpgradeMaxMinutes: number?,
	zone2MaxMinutes: number?,
	zone3MaxMinutes: number?,
}

export type Violation = {
	name: string,
	limit: number,
	actual: number?,
}

export type CheckResult = {
	ok: boolean,
	violations: { Violation },
}

local function minutes(seconds: number): number
	return math.floor(seconds / 60 * 100 + 0.5) / 100
end

local Simulator = {}

function Simulator.run(config: Schema.GameConfig, options: Options): Report
	local validation = Validator.validate(config)
	if not validation.ok then
		error("Simulator: invalid config\n" .. Validator.format(validation), 0)
	end
	assert(type(options) == "table", "Simulator: options must be set")
	assert(
		type(options.maxMinutes) == "number" and options.maxMinutes > 0 and options.maxMinutes < math.huge,
		"Simulator: maxMinutes must be a finite number > 0"
	)
	assert(options.buyPolicy == "cheapest_first", "Simulator: unknown buyPolicy " .. tostring(options.buyPolicy))

	local zoneOrder: { string } = {}
	for zoneId in config.zones do
		table.insert(zoneOrder, zoneId)
	end
	table.sort(zoneOrder, function(a: string, b: string): boolean
		return config.zones[a].order < config.zones[b].order
	end)

	-- Gewichteter Durchschnittspreis je Zone.
	local averagePrice: { [string]: number } = {}
	do
		local weightSum: { [string]: number } = {}
		local valueSum: { [string]: number } = {}
		for _, item in config.items do
			weightSum[item.zoneId] = (weightSum[item.zoneId] or 0) + item.spawnWeight
			valueSum[item.zoneId] = (valueSum[item.zoneId] or 0) + item.spawnWeight * item.price
		end
		for zoneId, weight in weightSum do
			averagePrice[zoneId] = valueSum[zoneId] / weight
		end
	end

	local dimensions: { string } = {}
	local levels: { [string]: number } = {}
	for dimension in config.upgrades do
		table.insert(dimensions, dimension)
		levels[dimension] = 0
	end
	table.sort(dimensions)

	local function stat(name: string): number
		local add, mul = 0, 1
		for _, dimension in dimensions do
			local upgrade = config.upgrades[dimension]
			local entry = upgrade.levels[levels[dimension]]
			if upgrade.stat == name and entry ~= nil then
				add += entry.add or 0
				mul *= entry.mul or 1
			end
		end
		return math.max(0, ((config.game.base :: any)[name] + add) * mul)
	end

	local now = 0
	local coins = config.game.startCoins
	local unlocked = 1
	local firstSell: number? = nil
	local firstUpgrade: number? = nil
	local zoneTimes: { [number]: number? } = { [1] = 0 }
	local timeline: { TimelineEntry } = { { minute = 0, event = "zone_unlock " .. zoneOrder[1] } }

	-- Nach jedem Verkauf: erst Zone, sonst guenstigstes Upgrade, solange etwas moeglich ist.
	local function spend()
		while true do
			local nextZoneId = zoneOrder[unlocked + 1]
			if nextZoneId ~= nil then
				local condition = config.zones[nextZoneId].condition
				-- Kosten der Freischaltung (0 = Bedingung erfuellt, nichts wird verbraucht; nil = nicht moeglich).
				local met = (condition.type == "coinsAtLeast" and coins >= condition.amount)
					or (condition.type == "upgradeLevel" and (levels[condition.dimension] or 0) >= condition.level)
				local cost: number? = if met
					then 0
					elseif condition.type == "purchase" and coins >= condition.cost then condition.cost
					else nil
				if cost ~= nil then
					coins -= cost
					unlocked += 1
					zoneTimes[unlocked] = minutes(now)
					table.insert(timeline, { minute = minutes(now), event = "zone_unlock " .. nextZoneId })
					continue
				end
			end

			local best: string? = nil
			local bestCost = math.huge
			for _, dimension in dimensions do
				local nextLevel = config.upgrades[dimension].levels[levels[dimension] + 1]
				if nextLevel ~= nil and nextLevel.cost <= coins and nextLevel.cost < bestCost then
					best, bestCost = dimension, nextLevel.cost
				end
			end
			if best == nil then
				return
			end
			coins -= bestCost
			levels[best] += 1
			if firstUpgrade == nil then
				firstUpgrade = minutes(now)
			end
			table.insert(
				timeline,
				{ minute = minutes(now), event = string.format("upgrade %s %d", best, levels[best]) }
			)
		end
	end

	spend()
	local limitSeconds = options.maxMinutes * 60
	while unlocked < #zoneOrder do
		local zoneId: string? = nil
		for rank = unlocked, 1, -1 do
			if config.zones[zoneOrder[rank]].density > 0 then
				zoneId = zoneOrder[rank]
				break
			end
		end
		if zoneId == nil then
			break
		end
		local zone = config.zones[zoneId]
		local rateLimit = config.collect.rateLimit
		local spawnRate = if zone.respawnSeconds > 0 then zone.density / zone.respawnSeconds else math.huge
		local rate = math.min(spawnRate, rateLimit.maxItems / rateLimit.windowSeconds)
		local capacity = math.floor(stat("capacity"))
		if rate <= 0 or capacity <= 0 then
			break
		end
		local cycle = capacity / rate + config.sim.tripSeconds + config.sim.sellSeconds
		if now + cycle > limitSeconds then
			break
		end
		now += cycle
		coins += math.floor(capacity * averagePrice[zoneId] * stat("sellFactor"))
		if firstSell == nil then
			firstSell = minutes(now)
			table.insert(timeline, { minute = minutes(now), event = "first_sell" })
		end
		spend()
	end

	return {
		minutesToFirstSell = firstSell,
		minutesToFirstUpgrade = firstUpgrade,
		minutesToZone = zoneTimes,
		reachedAllZones = unlocked == #zoneOrder,
		coinsAtEnd = coins,
		upgradeLevels = levels,
		timeline = timeline,
	}
end

-- Prueft einen Report gegen Grenzminuten. Ein nicht erreichtes Ziel (nil) ist immer eine Verletzung.
function Simulator.check(report: Report, limits: Limits): CheckResult
	local checks = {
		{
			name = "firstUpgradeMaxMinutes",
			limit = limits.firstUpgradeMaxMinutes,
			actual = report.minutesToFirstUpgrade,
		},
		{ name = "zone2MaxMinutes", limit = limits.zone2MaxMinutes, actual = report.minutesToZone[2] },
		{ name = "zone3MaxMinutes", limit = limits.zone3MaxMinutes, actual = report.minutesToZone[3] },
	}
	local violations: { Violation } = {}
	for _, entry in checks do
		local limit = entry.limit
		if limit ~= nil and (entry.actual == nil or (entry.actual :: number) > limit) then
			table.insert(violations, { name = entry.name, limit = limit, actual = entry.actual })
		end
	end
	return { ok = #violations == 0, violations = violations }
end

return Simulator
