--!strict
-- Reine Logik des HUD: macht aus einem ClientState-Schnappschuss und der Game-Config (Texte, Upgrade- und
-- Zonen-Daten) ein Anzeigemodell. Keine Instanzen, keine Spielentscheidungen: Ob etwas wirklich klappt,
-- entscheidet der Server; "affordable"/"canUnlock" dienen nur der Anzeige.
--
-- Text-Schluessel (aus config.texts, Platzhalter in {}): hud_coins {coins}, hud_inventory {count} {capacity},
-- hud_full, hud_level {level} {maxLevel}, hud_cost {cost}, hud_max, hud_zone_purchase {zone} {cost},
-- hud_zone_level {zone} {upgrade} {level}, hud_zone_coins {zone} {amount}, hud_zone_all, hud_unlock, hud_upgrades (Standard "Upgrades"), hud_collect,
-- hud_sell. Die Zonen-Bedingung steht nur einmal (zoneText); der Unlock-Button traegt den kurzen Text hud_unlock.
local Text = require(script.Parent.Text)

export type UpgradeEntry = {
	dimension: string,
	name: string,
	levelText: string,
	costText: string,
	affordable: boolean,
	maxed: boolean,
}

export type Model = {
	coinsText: string,
	inventoryText: string,
	full: boolean,
	upgrades: { UpgradeEntry },
	nextZoneId: string?,
	zoneText: string,
	canUnlock: boolean,
	unlockText: string,
	upgradesText: string,
	sellEnabled: boolean,
	collectEnabled: boolean,
	collectText: string,
	sellText: string,
}

local HudModel = {}

local function nextLockedZone(snapshot: any): string?
	local best: string? = nil
	local bestOrder = math.huge
	for zoneId, zone in snapshot.zones do
		if not zone.unlocked and zone.order < bestOrder then
			best, bestOrder = zoneId, zone.order
		end
	end
	return best
end

function HudModel.build(snapshot: any, config: any, texts: { [string]: string }?): Model
	local strings = texts or config.texts or {}
	local full = snapshot.inventoryCount >= snapshot.capacity

	local dimensions = {}
	for dimension in snapshot.upgrades do
		table.insert(dimensions, dimension)
	end
	table.sort(dimensions)
	local upgrades: { UpgradeEntry } = {}
	for _, dimension in dimensions do
		local state = snapshot.upgrades[dimension]
		local upgradeConfig = config.upgrades[dimension]
		local maxed = state.nextCost == nil
		table.insert(upgrades, {
			dimension = dimension,
			name = Text.lookup(strings, if upgradeConfig then upgradeConfig.nameKey else dimension),
			levelText = Text.lookup(strings, "hud_level", { level = state.level, maxLevel = state.maxLevel }),
			costText = if maxed
				then Text.lookup(strings, "hud_max")
				else Text.lookup(strings, "hud_cost", {
					cost = state.nextCost,
				}),
			affordable = not maxed and snapshot.coins >= state.nextCost,
			maxed = maxed,
		})
	end

	local nextZoneId = nextLockedZone(snapshot)
	local zoneText = Text.lookup(strings, "hud_zone_all")
	local canUnlock = false
	if nextZoneId ~= nil then
		local zoneConfig = config.zones[nextZoneId]
		local zoneName = Text.lookup(strings, zoneConfig.nameKey)
		local condition = zoneConfig.condition
		if condition.type == "purchase" then
			zoneText = Text.lookup(strings, "hud_zone_purchase", { zone = zoneName, cost = condition.cost })
			canUnlock = snapshot.coins >= condition.cost
		elseif condition.type == "coinsAtLeast" then
			zoneText = Text.lookup(strings, "hud_zone_coins", { zone = zoneName, amount = condition.amount })
			canUnlock = snapshot.coins >= condition.amount
		elseif condition.type == "upgradeLevel" then
			local upgradeConfig = config.upgrades[condition.dimension]
			local upgradeName =
				Text.lookup(strings, if upgradeConfig then upgradeConfig.nameKey else condition.dimension)
			zoneText = Text.lookup(strings, "hud_zone_level", {
				zone = zoneName,
				upgrade = upgradeName,
				level = condition.level,
			})
			local state = snapshot.upgrades[condition.dimension]
			canUnlock = state ~= nil and state.level >= condition.level
		else
			zoneText = zoneName
		end
	end

	return {
		coinsText = Text.lookup(strings, "hud_coins", { coins = snapshot.coins }),
		inventoryText = Text.lookup(
			strings,
			"hud_inventory",
			{ count = snapshot.inventoryCount, capacity = snapshot.capacity }
		) .. (if full then " " .. Text.lookup(strings, "hud_full") else ""),
		full = full,
		upgrades = upgrades,
		nextZoneId = nextZoneId,
		zoneText = zoneText,
		canUnlock = canUnlock,
		unlockText = Text.lookup(strings, "hud_unlock"),
		upgradesText = if strings.hud_upgrades ~= nil then strings.hud_upgrades else "Upgrades",
		sellEnabled = snapshot.inventoryCount > 0,
		-- Nur Anzeige: volles Inventar lehnt der Server ohnehin ab.
		collectEnabled = not full,
		collectText = Text.lookup(strings, "hud_collect"),
		sellText = Text.lookup(strings, "hud_sell"),
	}
end

return HudModel
