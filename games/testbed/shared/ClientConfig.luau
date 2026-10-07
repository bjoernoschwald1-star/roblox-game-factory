--!strict
-- Client-Teil der Testbed-Config (ReplicatedStorage.TestbedShared.ClientConfig): ausschliesslich Sichtbares.
-- Enthaelt Texte, uiTokens, assetStyles, rarityStyles, lighting, effects und Anzeige-Daten zu Items (zoneId, asset,
-- nameKey, rarity), Zonen (order, nameKey, Bedingung fuer den Anzeigetext) und Upgrades (nameKey).
-- Nie hier: Preise, Spawn-Gewichte, products, passes, remotes, sim, productId/passId. Die vollstaendige Config nach
-- Schema baut games/testbed/server/ServerConfig.luau aus diesen Daten plus den Spielwerten (nur Server).
-- Keine Assets: Formen, Farben und Licht nur ueber Eigenschaften.

local items = {
	item_small = { zoneId = "zone_a", asset = "item_small", nameKey = "item_small_name", rarity = "common" },
	item_medium = { zoneId = "zone_a", asset = "item_medium", nameKey = "item_medium_name", rarity = "common" },
	item_a_rare = { zoneId = "zone_a", asset = "item_rare", nameKey = "item_rare_name", rarity = "rare" },
	item_a_epic = { zoneId = "zone_a", asset = "item_epic", nameKey = "item_epic_name", rarity = "epic" },
	item_a_legendary = {
		zoneId = "zone_a",
		asset = "item_legendary",
		nameKey = "item_legendary_name",
		rarity = "legendary",
	},
	item_large = { zoneId = "zone_b", asset = "item_large", nameKey = "item_large_name", rarity = "common" },
	item_b_rare = { zoneId = "zone_b", asset = "item_rare", nameKey = "item_rare_name", rarity = "rare" },
	item_b_epic = { zoneId = "zone_b", asset = "item_epic", nameKey = "item_epic_name", rarity = "epic" },
	item_b_legendary = {
		zoneId = "zone_b",
		asset = "item_legendary",
		nameKey = "item_legendary_name",
		rarity = "legendary",
	},
	item_huge = { zoneId = "zone_c", asset = "item_huge", nameKey = "item_huge_name", rarity = "common" },
	item_c_rare = { zoneId = "zone_c", asset = "item_rare", nameKey = "item_rare_name", rarity = "rare" },
	item_c_epic = { zoneId = "zone_c", asset = "item_epic", nameKey = "item_epic_name", rarity = "epic" },
	item_c_legendary = {
		zoneId = "zone_c",
		asset = "item_legendary",
		nameKey = "item_legendary_name",
		rarity = "legendary",
	},
}

local zones = {
	zone_a = { order = 1, nameKey = "zone_a_name", condition = { type = "always" } },
	zone_b = { order = 2, nameKey = "zone_b_name", condition = { type = "purchase", cost = 150 } },
	zone_c = {
		order = 3,
		nameKey = "zone_c_name",
		condition = { type = "upgradeLevel", dimension = "capacity", level = 2 },
	},
}

local upgrades = {
	range = { nameKey = "upgrade_range_name" },
	capacity = { nameKey = "upgrade_capacity_name" },
	sell_bonus = { nameKey = "upgrade_sell_bonus_name" },
}

local texts = {
	item_small_name = "Kleines Objekt",
	item_medium_name = "Mittleres Objekt",
	item_large_name = "Großes Objekt",
	item_huge_name = "Riesiges Objekt",
	item_rare_name = "Glänzendes Objekt",
	item_epic_name = "Funkelndes Objekt",
	item_legendary_name = "Strahlendes Objekt",
	rarity_common = "Gewöhnlich",
	rarity_rare = "Selten",
	rarity_epic = "Episch",
	rarity_legendary = "Legendär",
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
	hud_zone_purchase = "{zone}: {cost} Münzen",
	hud_zone_level = "{zone}: {upgrade} Stufe {level}",
	hud_zone_coins = "{zone}: ab {amount} Münzen",
	hud_zone_all = "Alle Zonen frei",
	hud_unlock = "Freischalten",
	hud_collect = "Einsammeln (E)",
	hud_sell = "Verkaufen (Q)",
	hint_full = "Inventar voll! Folge dem Strahl zur Verkaufsfläche.",
	onboarding_collect = "Lauf zu den Objekten und sammle sie ein (E oder automatisch).",
	onboarding_sell = "Bring dein Inventar zur Verkaufsfläche und verkaufe (Q).",
	onboarding_upgrade = "Kauf ein Upgrade.",
	onboarding_unlock = "Schalte Zone B frei.",
	feedback_collected = "+{count}",
	feedback_earned = "+{coins} Münzen",
	feedback_upgraded = "Upgrade: {upgrade}",
	feedback_unlocked = "Neu frei: {zone}",
	feedback_full = "Inventar voll!",
	feedback_found = "{rarity}! {item}",
	leaderstats_coins = "Münzen",
	leaderstats_zone = "Zone",
	sign_sell = "Verkaufen",
	system_load_failed = "Dein Spielstand konnte gerade nicht geladen werden. Bitte gleich erneut beitreten.",
}

-- Form, Farbe und Groesse je asset-Schluessel (Studs).
local assetStyles = {
	item_small = { shape = "Ball", color = Color3.fromRGB(120, 200, 255), size = 1.2 },
	item_medium = { shape = "Block", color = Color3.fromRGB(255, 170, 90), size = 1.5 },
	item_large = { shape = "Cylinder", color = Color3.fromRGB(110, 220, 140), size = 2 },
	item_huge = { shape = "Block", color = Color3.fromRGB(255, 120, 150), size = 2.4 },
	item_rare = { shape = "Ball", color = Color3.fromRGB(70, 140, 255), size = 1.4 },
	item_epic = { shape = "Block", color = Color3.fromRGB(180, 90, 255), size = 1.5 },
	item_legendary = { shape = "Ball", color = Color3.fromRGB(255, 200, 40), size = 1.6 },
}

-- Darstellung je Seltenheit; fehlende Felder ergaenzt das Kit (ItemView.DEFAULT_RARITY_STYLES).
local rarityStyles = {
	common = {},
	rare = { accent = Color3.fromRGB(90, 170, 255) },
	epic = { accent = Color3.fromRGB(200, 110, 255) },
	legendary = { accent = Color3.fromRGB(255, 210, 60) },
}

-- Freundliche, satte Tageslicht-Stimmung (kit/src/LightingProfile.luau, vom Server-Skript angewandt).
local lighting = {
	properties = {
		-- TimeOfDay statt ClockTime: ClockTime ist laut Doku NotReplicated, der Server setzt die Werte.
		TimeOfDay = "14:12:00",
		Brightness = 2.6,
		Ambient = Color3.fromRGB(90, 90, 110),
		OutdoorAmbient = Color3.fromRGB(150, 150, 170),
		ColorShift_Top = Color3.fromRGB(255, 240, 215),
		ColorShift_Bottom = Color3.fromRGB(150, 180, 255),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.8,
		GlobalShadows = true,
		ExposureCompensation = 0.1,
	},
	atmosphere = {
		Density = 0.28,
		Offset = 0.15,
		Color = Color3.fromRGB(200, 225, 255),
		Decay = Color3.fromRGB(120, 160, 220),
		Glare = 0.2,
		Haze = 0.6,
	},
	colorCorrection = {
		Brightness = 0.03,
		Contrast = 0.1,
		Saturation = 0.25,
		TintColor = Color3.fromRGB(255, 252, 245),
	},
	bloom = { Intensity = 0.6, Size = 28, Threshold = 1.2 },
	sunRays = { Intensity = 0.06, Spread = 0.6 },
	sky = { SunAngularSize = 14, MoonAngularSize = 9, StarCount = 1500, CelestialBodiesShown = true },
}

-- Effekt-Tabelle des Feedbacks (kit/src/FeedbackView.luau). sounds bleibt im Testbed leer: keine Sound-Assets.
local effects = {
	collected = { textKey = "feedback_collected", color = Color3.fromRGB(255, 255, 255) },
	earned = { textKey = "feedback_earned", color = Color3.fromRGB(255, 220, 90) },
	upgraded = { textKey = "feedback_upgraded", color = Color3.fromRGB(120, 220, 255) },
	unlocked = { textKey = "feedback_unlocked", color = Color3.fromRGB(140, 255, 140) },
	full = { textKey = "feedback_full", color = Color3.fromRGB(255, 120, 120) },
	found = { textKey = "feedback_found", color = Color3.fromRGB(200, 110, 255) },
	sounds = {},
}

local uiTokens = {
	background = Color3.fromRGB(25, 30, 45),
	panel = Color3.fromRGB(30, 40, 70),
	text = Color3.fromRGB(255, 255, 255),
	accent = Color3.fromRGB(40, 170, 110),
	disabled = Color3.fromRGB(95, 100, 115),
	highlight = Color3.fromRGB(255, 200, 40),
	highlightText = Color3.fromRGB(35, 30, 20),
	font = Enum.Font.GothamBold,
	textSize = 22,
	padding = 12,
}

return {
	items = items,
	zones = zones,
	upgrades = upgrades,
	texts = texts,
	assetStyles = assetStyles,
	rarityStyles = rarityStyles,
	lighting = lighting,
	effects = effects,
	uiTokens = uiTokens,
	onboardingSteps = nil,
}
