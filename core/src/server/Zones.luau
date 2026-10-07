--!strict
-- Logische Zonensperre (die sichtbare Sperre ist spaeter Presentation). Zonen haben eine feste Reihenfolge
-- (order); eine Zone kann erst freigeschaltet werden, wenn die vorherige frei ist. Die Startzone (kleinste
-- order, Bedingung "always") ist fuer jedes geladene Profil frei.
--
-- Freischaltbedingungen sind registrierbare Regeln (Erweiterungspunkt Zone-Bedingung): check prueft,
-- ein optionaler effect verbraucht etwas (z. B. Coins). Eingebaut: always, coinsAtLeast, purchase,
-- upgradeLevel. Ob alle verwendeten Bedingungstypen registriert sind, prueft validate() (nach allen
-- registerCondition-Aufrufen); tryUnlock meldet einen unbekannten Typ als UNKNOWN_CONDITION.
--
-- Gespeichert: profile[field] = { [zoneId]: true }. Fehlendes Feld = nur die Startzone frei (wird angelegt).
-- Ein vorhandener ungueltiger Wert (keine Tabelle, Schluessel kein nicht-leerer String, Wert nicht true) wird
-- nicht repariert: CORRUPT_VALUE; isUnlocked liefert dann nur fuer die Startzone true.
--
-- Fehlercodes tryUnlock: UNKNOWN_ZONE, NOT_LOADED, CORRUPT_VALUE, ALREADY_UNLOCKED, PREVIOUS_LOCKED,
-- UNKNOWN_CONDITION, MISSING_DEPENDENCY, CONDITION_NOT_MET (dritter Rueckgabewert: Grund aus check),
-- CONDITION_ERROR (check/effect hat geworfen) sowie Fehler aus effect.
local Economy = require(script.Parent.Economy)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)
local Upgrades = require(script.Parent.Upgrades)

type PlayerContext = PlayerContext.PlayerContext
type Profile = { [string]: any }

export type Condition = { type: string, [string]: any }

export type ZoneConfig = {
	order: number,
	condition: Condition,
}

export type Check = (ctx: PlayerContext, params: Condition) -> (boolean, string?)
export type Effect = (ctx: PlayerContext, params: Condition) -> (boolean, string?)

export type Options = {
	getProfile: (ctx: PlayerContext) -> Profile?,
	field: string?,
	zones: { [string]: ZoneConfig },
	economy: Economy.Economy?,
	upgrades: Upgrades.Upgrades?,
	onUnlocked: ((ctx: PlayerContext, event: { zoneId: string }) -> ())?,
}

export type Zones = {
	registerCondition: (self: Zones, conditionType: string, check: Check, effect: Effect?) -> (),
	validate: (self: Zones) -> (boolean, string?),
	isUnlocked: (self: Zones, ctx: PlayerContext, zoneId: string) -> boolean,
	tryUnlock: (self: Zones, ctx: PlayerContext, zoneId: string) -> (boolean, string?, string?),
	unlockedZones: (self: Zones, ctx: PlayerContext) -> { string }?,
}

type Rule = {
	check: Check,
	effect: Effect?,
}

local DEFAULT_FIELD = "zones"

local function isWholePositive(value: any): boolean
	return type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value)
end

local Zones = {}

function Zones.new(options: Options): Zones
	assert(type(options.getProfile) == "function", "Zones: getProfile must be a function")
	local field = options.field or DEFAULT_FIELD
	assert(type(field) == "string" and field ~= "", "Zones: field must be a non-empty string")
	assert(type(options.zones) == "table", "Zones: zones must be a table")

	local ordered: { string } = {}
	local usedOrders: { [number]: string } = {}
	for zoneId, zone in options.zones do
		assert(type(zoneId) == "string" and zoneId ~= "", "Zones: zone ids must be non-empty strings")
		assert(
			type(zone.order) == "number" and zone.order == math.floor(zone.order) and math.abs(zone.order) < math.huge,
			"Zones: order of " .. zoneId .. " must be a whole number"
		)
		assert(usedOrders[zone.order] == nil, "Zones: order " .. zone.order .. " is used twice")
		assert(
			type(zone.condition) == "table" and type(zone.condition.type) == "string",
			"Zones: " .. zoneId .. " needs a condition with a type"
		)
		usedOrders[zone.order] = zoneId
		table.insert(ordered, zoneId)
	end
	assert(#ordered >= 1, "Zones: at least one zone is required")
	table.sort(ordered, function(a: string, b: string): boolean
		return options.zones[a].order < options.zones[b].order
	end)
	for index, zoneId in ordered do
		local isAlways = options.zones[zoneId].condition.type == "always"
		if index == 1 then
			assert(isAlways, "Zones: the zone with the lowest order must use condition always")
		else
			assert(not isAlways, "Zones: only the zone with the lowest order may use condition always")
		end
	end

	local getProfile = options.getProfile
	local zones = options.zones
	local economy = options.economy
	local upgrades = options.upgrades
	local onUnlocked = options.onUnlocked
	local startZone = ordered[1]
	local previousOf: { [string]: string } = {}
	for index = 2, #ordered do
		previousOf[ordered[index]] = ordered[index - 1]
	end

	local rules: { [string]: Rule } = {}

	-- Liefert die Tabelle der freien Zonen; ein fehlendes Feld wird angelegt. nil = vorhandener Wert ungueltig.
	local function unlockedSet(profile: Profile): { [string]: boolean }?
		local stored = profile[field]
		if stored == nil then
			stored = {}
			profile[field] = stored
			return stored
		end
		if type(stored) ~= "table" then
			return nil
		end
		for zoneId, value in stored do
			if type(zoneId) ~= "string" or zoneId == "" or value ~= true then
				return nil
			end
		end
		return stored
	end

	local function isFree(stored: { [string]: boolean }, zoneId: string): boolean
		return zoneId == startZone or stored[zoneId] == true
	end

	local registry: Zones

	registry = {
		registerCondition = function(_self, conditionType: string, check: Check, effect: Effect?)
			assert(type(conditionType) == "string" and conditionType ~= "", "Zones: condition type must be a string")
			assert(rules[conditionType] == nil, "Zones: condition " .. conditionType .. " is already registered")
			assert(type(check) == "function", "Zones: check must be a function")
			assert(effect == nil or type(effect) == "function", "Zones: effect must be a function")
			rules[conditionType] = { check = check, effect = effect }
		end,

		validate = function(_self): (boolean, string?)
			for _, zoneId in ordered do
				local conditionType = zones[zoneId].condition.type
				if rules[conditionType] == nil then
					return false, string.format("UNKNOWN_CONDITION: %s uses %s", zoneId, conditionType)
				end
			end
			return true, nil
		end,

		isUnlocked = function(_self, ctx: PlayerContext, zoneId: string): boolean
			if zones[zoneId] == nil then
				return false
			end
			local profile = getProfile(ctx)
			if profile == nil then
				return false
			end
			if zoneId == startZone then
				return true
			end
			local stored = unlockedSet(profile)
			return stored ~= nil and stored[zoneId] == true
		end,

		tryUnlock = function(_self, ctx: PlayerContext, zoneId: string): (boolean, string?, string?)
			local zone = zones[zoneId]
			if zone == nil then
				return false, "UNKNOWN_ZONE"
			end
			local profile = getProfile(ctx)
			if profile == nil then
				return false, "NOT_LOADED"
			end
			local stored = unlockedSet(profile)
			if stored == nil then
				return false, "CORRUPT_VALUE"
			end
			if isFree(stored, zoneId) then
				return false, "ALREADY_UNLOCKED"
			end
			if not isFree(stored, previousOf[zoneId]) then
				return false, "PREVIOUS_LOCKED"
			end
			local rule = rules[zone.condition.type]
			if rule == nil then
				return false, "UNKNOWN_CONDITION"
			end

			local checkOk, met, reason = pcall(rule.check, ctx, zone.condition)
			if not checkOk then
				warn("[Zones] condition " .. zone.condition.type .. " failed: " .. tostring(met))
				return false, "CONDITION_ERROR"
			end
			if not met then
				if reason == "MISSING_DEPENDENCY" then
					return false, "MISSING_DEPENDENCY"
				end
				return false, "CONDITION_NOT_MET", reason
			end
			if rule.effect ~= nil then
				local effectOk, applied, effectErr = pcall(rule.effect, ctx, zone.condition)
				if not effectOk then
					warn("[Zones] effect of " .. zone.condition.type .. " failed: " .. tostring(applied))
					return false, "CONDITION_ERROR"
				end
				if not applied then
					return false, effectErr or "EFFECT_FAILED"
				end
			end

			stored[zoneId] = true
			if onUnlocked then
				local ok, callbackErr = pcall(onUnlocked, ctx, { zoneId = zoneId })
				if not ok then
					warn("[Zones] onUnlocked failed: " .. tostring(callbackErr))
				end
			end
			return true, nil
		end,

		unlockedZones = function(_self, ctx: PlayerContext): { string }?
			local profile = getProfile(ctx)
			if profile == nil then
				return nil
			end
			local stored = unlockedSet(profile)
			if stored == nil then
				return nil
			end
			local list = {}
			for _, zoneId in ordered do
				if isFree(stored, zoneId) then
					table.insert(list, zoneId)
				end
			end
			return list
		end,
	}

	-- Eingebaute Bedingungen.
	registry:registerCondition("always", function(): (boolean, string?)
		return true, nil
	end)

	registry:registerCondition("coinsAtLeast", function(ctx: PlayerContext, params: Condition): (boolean, string?)
		if economy == nil then
			return false, "MISSING_DEPENDENCY"
		end
		if not isWholePositive(params.amount) then
			return false, "INVALID_PARAMS"
		end
		local balance = economy:balance(ctx)
		if balance == nil then
			return false, "BALANCE_UNAVAILABLE"
		end
		return balance >= params.amount, if balance >= params.amount then nil else "INSUFFICIENT_FUNDS"
	end)

	registry:registerCondition("purchase", function(ctx: PlayerContext, params: Condition): (boolean, string?)
		if economy == nil then
			return false, "MISSING_DEPENDENCY"
		end
		if not isWholePositive(params.cost) then
			return false, "INVALID_PARAMS"
		end
		local balance = economy:balance(ctx)
		if balance == nil then
			return false, "BALANCE_UNAVAILABLE"
		end
		return balance >= params.cost, if balance >= params.cost then nil else "INSUFFICIENT_FUNDS"
	end, function(ctx: PlayerContext, params: Condition): (boolean, string?)
		return (economy :: Economy.Economy):debit(ctx, params.cost, "zone_unlock")
	end)

	registry:registerCondition("upgradeLevel", function(ctx: PlayerContext, params: Condition): (boolean, string?)
		if upgrades == nil then
			return false, "MISSING_DEPENDENCY"
		end
		if type(params.dimension) ~= "string" or not isWholePositive(params.level) then
			return false, "INVALID_PARAMS"
		end
		local level = upgrades:level(ctx, params.dimension)
		if level == nil then
			return false, "UPGRADE_UNAVAILABLE"
		end
		return level >= params.level, if level >= params.level then nil else "LEVEL_TOO_LOW"
	end)

	return registry
end

return Zones
