--!strict
-- Theme-neutrale, gueltige Beispiel-Config fuer Tests. Liefert bei jedem Aufruf eine frische Kopie, damit Tests
-- sie gezielt kaputt machen koennen, ohne einander zu beeinflussen. Product- und Pass-IDs sind Platzhalter.
local Schema = require(game:GetService("ServerScriptService").FactoryCore.server.Config.Schema)

return function(): Schema.GameConfig
	return {
		game = {
			id = "sample_game",
			configVersion = "1.0.0",
			startCoins = 20,
			schemaVersion = 1,
			base = { range = 10, capacity = 10, sellFactor = 1 },
		},
		items = {
			item_small = {
				zoneId = "zone_a",
				spawnWeight = 3,
				price = 2,
				asset = "item_small",
				nameKey = "item_small_name",
			},
			item_medium = {
				zoneId = "zone_a",
				spawnWeight = 1,
				price = 5,
				asset = "item_medium",
				nameKey = "item_medium_name",
			},
			item_large = {
				zoneId = "zone_b",
				spawnWeight = 2,
				price = 8,
				asset = "item_large",
				nameKey = "item_large_name",
			},
			item_rare = {
				zoneId = "zone_b",
				spawnWeight = 1,
				price = 20,
				asset = "item_rare",
				nameKey = "item_rare_name",
			},
			item_huge = {
				zoneId = "zone_c",
				spawnWeight = 1,
				price = 40,
				asset = "item_huge",
				nameKey = "item_huge_name",
			},
		},
		zones = {
			zone_a = {
				order = 1,
				density = 8,
				respawnSeconds = 4,
				condition = { type = "always" },
				nameKey = "zone_a_name",
			},
			zone_b = {
				order = 2,
				density = 10,
				respawnSeconds = 4,
				condition = { type = "purchase", cost = 300 },
				nameKey = "zone_b_name",
			},
			zone_c = {
				order = 3,
				density = 12,
				respawnSeconds = 4,
				condition = { type = "upgradeLevel", dimension = "capacity", level = 2 },
				nameKey = "zone_c_name",
			},
		},
		upgrades = {
			range = {
				stat = "range",
				levels = { { cost = 50, add = 5 }, { cost = 150, add = 10 } },
				nameKey = "upgrade_range_name",
			},
			capacity = {
				stat = "capacity",
				levels = { { cost = 100, add = 10 }, { cost = 400, add = 25 }, { cost = 1200, add = 50 } },
				nameKey = "upgrade_capacity_name",
			},
			sell_bonus = {
				stat = "sellFactor",
				levels = { { cost = 250, mul = 1.25 }, { cost = 800, mul = 1.5 } },
				nameKey = "upgrade_sell_bonus_name",
			},
		},
		collect = {
			type = "radius",
			params = {},
			rangeTolerance = 2,
			rateLimit = { maxItems = 20, windowSeconds = 10 },
		},
		sell = { trigger = "zone" },
		products = {
			coins_small = { productId = 1, rewards = { { type = "coins", amount = 500 } } },
			bundle_vip = {
				productId = 2,
				rewards = { { type = "coins", amount = 1000 }, { type = "perk", perkId = "vip" } },
			},
		},
		passes = {
			double_range = { passId = 1, effects = { range = { mul = 2 } } },
		},
		remotes = {
			collect = { max = 10, windowSeconds = 1 },
			sell = { max = 5, windowSeconds = 1 },
			buyUpgrade = { max = 5, windowSeconds = 1 },
			unlockZone = { max = 5, windowSeconds = 1 },
			prestige = { max = 1, windowSeconds = 2 },
		},
		texts = {
			item_small_name = "Small item",
			item_medium_name = "Medium item",
			item_large_name = "Large item",
			item_rare_name = "Rare item",
			item_huge_name = "Huge item",
			zone_a_name = "Zone A",
			zone_b_name = "Zone B",
			zone_c_name = "Zone C",
			upgrade_range_name = "Range",
			upgrade_capacity_name = "Capacity",
			upgrade_sell_bonus_name = "Sell bonus",
		},
		sim = { tripSeconds = 10, sellSeconds = 5 },
	}
end
