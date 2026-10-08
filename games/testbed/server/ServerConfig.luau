--!strict
-- Server-Teil der Testbed-Config (nur ServerScriptService): vollstaendige Game-Config nach dem Core-Schema.
-- Anzeige-Daten (Items, Zonen, Upgrade-Namen, Texte) kommen aus ReplicatedStorage.TestbedShared.ClientConfig und
-- werden hier um die Spielwerte ergaenzt (spawnWeight, price, density, respawnSeconds, Upgrade-Stufen, collect,
-- sell, remotes, sim). Seltene Stufen: eigene Itemtypen mit deutlich kleinerem spawnWeight und hoeherem price.
-- Testbed ohne Produkte und Paesse (Entscheidung Bjoern): products = {}, passes = {} - keine Marketplace-Abfragen.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClientConfig = require(ReplicatedStorage:WaitForChild("TestbedShared"):WaitForChild("ClientConfig"))

-- Spielwerte je Itemtyp: Gewicht relativ innerhalb der Zone, Verkaufspreis in Coins.
local ITEM_VALUES: { [string]: { spawnWeight: number, price: number } } = {
	item_small = { spawnWeight = 3, price = 2 },
	item_medium = { spawnWeight = 1, price = 5 },
	item_a_rare = { spawnWeight = 0.4, price = 12 },
	item_a_epic = { spawnWeight = 0.1, price = 35 },
	item_a_legendary = { spawnWeight = 0.025, price = 100 },
	item_large = { spawnWeight = 2, price = 8 },
	item_b_rare = { spawnWeight = 0.5, price = 25 },
	item_b_epic = { spawnWeight = 0.12, price = 70 },
	item_b_legendary = { spawnWeight = 0.03, price = 200 },
	item_huge = { spawnWeight = 1, price = 40 },
	item_c_rare = { spawnWeight = 0.3, price = 100 },
	item_c_epic = { spawnWeight = 0.08, price = 250 },
	item_c_legendary = { spawnWeight = 0.02, price = 700 },
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
	local values = ITEM_VALUES[itemId]
	items[itemId] = {
		zoneId = display.zoneId,
		asset = display.asset,
		nameKey = display.nameKey,
		rarity = display.rarity,
		spawnWeight = if values then values.spawnWeight else nil,
		price = if values then values.price else nil,
	}
end

local zones = {}
for zoneId, display in ClientConfig.zones do
	local values = ZONE_VALUES[zoneId]
	zones[zoneId] = {
		order = display.order,
		nameKey = display.nameKey,
		condition = table.clone(display.condition),
		density = if values then values.density else nil,
		respawnSeconds = if values then values.respawnSeconds else nil,
	}
end

local upgrades = {}
for dimension, display in ClientConfig.upgrades do
	local values = UPGRADE_VALUES[dimension]
	upgrades[dimension] = {
		nameKey = display.nameKey,
		stat = if values then values.stat else nil,
		levels = if values then values.levels else nil,
	}
end

local config = {
	game = {
		id = "testbed",
		configVersion = "0.2.0",
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
		-- Auto-Einsammeln sendet hoechstens 4 collect pro Sekunde; dazu Tasten und Touch.
		collect = { max = 10, windowSeconds = 1 },
		sell = { max = 5, windowSeconds = 1 },
		buyUpgrade = { max = 5, windowSeconds = 1 },
		unlockZone = { max = 5, windowSeconds = 1 },
		prestige = { max = 1, windowSeconds = 2 },
	},
	texts = ClientConfig.texts,
	sim = { tripSeconds = 8, sellSeconds = 4 },
}

return config
