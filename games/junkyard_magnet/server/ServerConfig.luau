--!strict
-- Server-Teil der Junkyard-Magnet-Config (nur ServerScriptService): vollstaendige Game-Config nach dem Core-Schema.
-- Anzeige-Daten kommen aus ReplicatedStorage.JunkyardShared.ClientConfig; hier kommen die Spielwerte dazu.
-- Spawn-Gewicht und Preis ergeben sich aus Zone und Seltenheit (seltene Stufen: viel kleineres Gewicht, hoeherer
-- Preis); die Werte folgen dem Testbed, dessen Simulator alle drei Zonen erreicht.
-- Vorerst ohne Produkte und Paesse (keine Marketplace-Abfragen; Preise sind ein manuelles Gate).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientConfig = require(ReplicatedStorage:WaitForChild("JunkyardShared"):WaitForChild("ClientConfig"))

-- Je Zone: Grundpreis der gewoehnlichen Teile; Faktoren und Gewichte je Seltenheit.
local ZONE_BASE_PRICE: { [string]: number } = { zone_a = 3, zone_b = 8, zone_c = 40 }
local RARITY_VALUES: { [string]: { weight: number, priceFactor: number } } = {
	common = { weight = 2, priceFactor = 1 },
	rare = { weight = 0.4, priceFactor = 4 },
	epic = { weight = 0.1, priceFactor = 12 },
	legendary = { weight = 0.025, priceFactor = 35 },
}

local ZONE_VALUES: { [string]: { density: number, respawnSeconds: number } } = {
	zone_a = { density = 10, respawnSeconds = 3 },
	zone_b = { density = 12, respawnSeconds = 3 },
	zone_c = { density = 14, respawnSeconds = 3 },
}

local UPGRADE_VALUES: { [string]: { stat: string, levels: { any } } } = {
	range = { stat = "range", levels = { { cost = 50, add = 4 }, { cost = 150, add = 8 } } },
	capacity = {
		stat = "capacity",
		levels = { { cost = 80, add = 10 }, { cost = 300, add = 20 }, { cost = 900, add = 40 } },
	},
	sell_bonus = { stat = "sellFactor", levels = { { cost = 200, mul = 1.25 }, { cost = 700, mul = 1.5 } } },
}

local items = {}
for itemId, display in ClientConfig.items do
	local values = RARITY_VALUES[display.rarity] or RARITY_VALUES.common
	items[itemId] = {
		zoneId = display.zoneId,
		asset = display.asset,
		nameKey = display.nameKey,
		rarity = display.rarity,
		spawnWeight = values.weight,
		price = math.max(1, math.floor(ZONE_BASE_PRICE[display.zoneId] * values.priceFactor)),
	}
end

local zones = {}
for zoneId, display in ClientConfig.zones do
	local values = ZONE_VALUES[zoneId]
	zones[zoneId] = {
		order = display.order,
		nameKey = display.nameKey,
		condition = table.clone(display.condition),
		density = values.density,
		respawnSeconds = values.respawnSeconds,
	}
end

local upgrades = {}
for dimension, display in ClientConfig.upgrades do
	local values = UPGRADE_VALUES[dimension]
	upgrades[dimension] = { nameKey = display.nameKey, stat = values.stat, levels = values.levels }
end

return {
	game = {
		id = "junkyard_magnet",
		configVersion = "0.1.0",
		startCoins = 0,
		schemaVersion = 1,
		base = { range = 12, capacity = 10, sellFactor = 1 },
	},
	items = items,
	zones = zones,
	upgrades = upgrades,
	collect = {
		type = "radius",
		params = {},
		rangeTolerance = 2,
		rateLimit = { maxItems = 40, windowSeconds = 10 },
	},
	sell = { trigger = "zone" },
	products = {},
	passes = {},
	remotes = {
		collect = { max = 10, windowSeconds = 1 },
		sell = { max = 5, windowSeconds = 1 },
		buyUpgrade = { max = 5, windowSeconds = 1 },
		unlockZone = { max = 5, windowSeconds = 1 },
	},
	texts = ClientConfig.texts,
	sim = { tripSeconds = 8, sellSeconds = 4 },
}
