--!strict
-- Server-Teil der Junkyard-Magnet-Config (nur ServerScriptService): vollstaendige Game-Config nach dem Core-Schema.
-- Anzeige-Daten kommen aus ReplicatedStorage.JunkyardShared.ClientConfig; hier kommen die Spielwerte dazu.
-- Spawn-Gewicht und Preis ergeben sich aus Zone und Seltenheit (seltene Stufen: viel kleineres Gewicht, hoeherer
-- Preis); die Werte folgen dem Testbed, dessen Simulator alle drei Zonen erreicht.
-- Vorerst ohne Produkte und Paesse (keine Marketplace-Abfragen; Preise sind ein manuelles Gate).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientConfig = require(ReplicatedStorage:WaitForChild("JunkyardShared"):WaitForChild("ClientConfig"))

-- Je Zone: Grundpreis der gewoehnlichen Teile; Faktoren und Gewichte je Seltenheit.
local ZONE_BASE_PRICE: { [string]: number } = { zone_a = 3, zone_b = 8, zone_c = 20, zone_d = 45 }
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
	zone_d = { density = 16, respawnSeconds = 3 },
}

local UPGRADE_VALUES: { [string]: { stat: string, levels: { any } } } = {
	range = {
		stat = "range",
		levels = {
			{ cost = 60, add = 3 },
			{ cost = 550, add = 6 },
			{ cost = 3200, add = 10 },
			{ cost = 12900, add = 15 },
		},
	},
	capacity = {
		stat = "capacity",
		levels = {
			{ cost = 100, add = 8 },
			{ cost = 1000, add = 18 },
			{ cost = 4900, add = 30 },
			{ cost = 16100, add = 50 },
			{ cost = 48300, add = 80 },
		},
	},
	sell_bonus = {
		stat = "sellFactor",
		levels = {
			{ cost = 400, mul = 1.2 },
			{ cost = 8100, mul = 1.45 },
			{ cost = 29000, mul = 1.75 },
			{ cost = 80500, mul = 2.1 },
		},
	},
}

-- Sammelalbum: je vollstaendiger Reihe einmalig Muenzen und dauerhaft +3 % Verkauf (6 Reihen zusammen etwa
-- x1,19; bleibt nach der Schmelze). Spuerbar, aber klein gegen den Haendlerbonus (bis x2,1) und die Schmelze (x1,5).
local ALBUM_REWARD = { coins = 3000, effects = { sellFactor = { mul = 1.03 } } }

-- Schmelze (Prestige im Kern): Schwelle und dauerhafter Bonus je Stufe.
local PRESTIGE = { coinsRequired = 200000, sellBonusPerLevel = 0.5 }

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

local albumGroups = {}
for groupId, group in ClientConfig.albumGroups do
	albumGroups[groupId] = {
		order = group.order,
		nameKey = group.nameKey,
		entries = group.entries,
		reward = ALBUM_REWARD,
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
		prestige = { max = 1, windowSeconds = 2 },
	},
	texts = ClientConfig.texts,
	sim = { tripSeconds = 8, sellSeconds = 4 },
	prestige = PRESTIGE,
	collection = { groups = albumGroups },
}
