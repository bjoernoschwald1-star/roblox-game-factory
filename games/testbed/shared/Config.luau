--!strict
-- Testbed: theme-neutrales erstes Game zum Durchspielen des Loops (einsammeln -> verkaufen -> upgraden ->
-- naechste Zone). Graue Flaechen, einfache Formen, keine Assets. Product- und Pass-IDs sind Platzhalter;
-- das Testbed zeigt keine Kauf-Buttons.
-- Exportiert: config (Game-Config nach dem Core-Schema), assetStyles (Form/Farbe je asset-Schluessel),
-- uiTokens (Farben, Schrift, Abstaende), onboardingSteps (nil = Kit-Standard).

local config = {
	game = {
		id = "testbed",
		configVersion = "0.1.0",
		startCoins = 0,
		schemaVersion = 1,
		base = { range = 12, capacity = 10, sellFactor = 1 },
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
		item_rare = { zoneId = "zone_b", spawnWeight = 1, price = 20, asset = "item_rare", nameKey = "item_rare_name" },
		item_huge = { zoneId = "zone_c", spawnWeight = 1, price = 40, asset = "item_huge", nameKey = "item_huge_name" },
	},
	zones = {
		zone_a = {
			order = 1,
			density = 10,
			respawnSeconds = 3,
			condition = { type = "always" },
			nameKey = "zone_a_name",
		},
		zone_b = {
			order = 2,
			density = 12,
			respawnSeconds = 3,
			condition = { type = "purchase", cost = 150 },
			nameKey = "zone_b_name",
		},
		zone_c = {
			order = 3,
			density = 14,
			respawnSeconds = 3,
			condition = { type = "upgradeLevel", dimension = "capacity", level = 2 },
			nameKey = "zone_c_name",
		},
	},
	upgrades = {
		range = {
			stat = "range",
			levels = { { cost = 50, add = 4 }, { cost = 150, add = 8 } },
			nameKey = "upgrade_range_name",
		},
		capacity = {
			stat = "capacity",
			levels = { { cost = 80, add = 10 }, { cost = 300, add = 20 }, { cost = 900, add = 40 } },
			nameKey = "upgrade_capacity_name",
		},
		sell_bonus = {
			stat = "sellFactor",
			levels = { { cost = 200, mul = 1.25 }, { cost = 700, mul = 1.5 } },
			nameKey = "upgrade_sell_bonus_name",
		},
	},
	collect = {
		type = "radius",
		params = {},
		rangeTolerance = 2,
		rateLimit = { maxItems = 40, windowSeconds = 10 },
	},
	sell = { trigger = "zone" },
	products = {
		coins_small = { productId = 1, rewards = { { type = "coins", amount = 500 } } },
	},
	passes = {
		double_range = { passId = 1, effects = { range = { mul = 2 } } },
	},
	remotes = {
		-- Auto-Einsammeln sendet hoechstens 4 collect pro Sekunde; dazu Tasten und Touch.
		collect = { max = 10, windowSeconds = 1 },
		sell = { max = 5, windowSeconds = 1 },
		buyUpgrade = { max = 5, windowSeconds = 1 },
		unlockZone = { max = 5, windowSeconds = 1 },
	},
	texts = {
		item_small_name = "Kleines Objekt",
		item_medium_name = "Mittleres Objekt",
		item_large_name = "Großes Objekt",
		item_rare_name = "Seltenes Objekt",
		item_huge_name = "Riesiges Objekt",
		zone_a_name = "Zone A",
		zone_b_name = "Zone B",
		zone_c_name = "Zone C",
		upgrade_range_name = "Reichweite",
		upgrade_capacity_name = "Kapazität",
		upgrade_sell_bonus_name = "Verkaufsbonus",
		hud_coins = "Münzen: {coins}",
		hud_inventory = "Inventar: {count} / {capacity}",
		hud_full = "(voll)",
		hud_level = "Stufe {level}/{maxLevel}",
		hud_cost = "{cost} Münzen",
		hud_max = "MAX",
		hud_zone_purchase = "{zone} freischalten: {cost} Münzen",
		hud_zone_level = "{zone} freischalten: {upgrade} Stufe {level}",
		hud_zone_coins = "{zone} freischalten: ab {amount} Münzen",
		hud_zone_all = "Alle Zonen frei",
		hud_collect = "Einsammeln (E)",
		hud_sell = "Verkaufen (Q)",
		onboarding_collect = "Lauf zu den Objekten und sammle sie ein (E oder automatisch).",
		onboarding_sell = "Bring dein Inventar zur Verkaufsfläche und verkaufe (Q).",
		onboarding_upgrade = "Kauf links ein Upgrade.",
		onboarding_unlock = "Schalte Zone B frei (Button oben).",
		feedback_collected = "+{count}",
		feedback_earned = "+{coins} Münzen",
		feedback_upgraded = "Upgrade: {upgrade}",
		feedback_unlocked = "Neu frei: {zone}",
		feedback_full = "Inventar voll!",
		system_load_failed = "Dein Spielstand konnte gerade nicht geladen werden. Bitte gleich erneut beitreten.",
	},
	sim = { tripSeconds = 8, sellSeconds = 4 },
}

local assetStyles = {
	item_small = { shape = "Ball", color = Color3.fromRGB(210, 210, 210), size = 1.2 },
	item_medium = { shape = "Block", color = Color3.fromRGB(170, 170, 170), size = 1.6 },
	item_large = { shape = "Cylinder", color = Color3.fromRGB(140, 160, 190), size = 2 },
	item_rare = { shape = "Ball", color = Color3.fromRGB(230, 200, 90), size = 1.6 },
	item_huge = { shape = "Block", color = Color3.fromRGB(120, 190, 140), size = 2.6 },
}

local uiTokens = {
	background = Color3.fromRGB(30, 30, 30),
	panel = Color3.fromRGB(45, 45, 45),
	text = Color3.fromRGB(245, 245, 245),
	accent = Color3.fromRGB(70, 130, 200),
	disabled = Color3.fromRGB(95, 95, 95),
	font = Enum.Font.GothamBold,
	textSize = 22,
	padding = 12,
}

return {
	config = config,
	assetStyles = assetStyles,
	uiTokens = uiTokens,
	onboardingSteps = nil,
}
