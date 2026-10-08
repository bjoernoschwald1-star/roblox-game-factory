--!strict
-- Client-Teil der Junkyard-Magnet-Config (ReplicatedStorage.JunkyardShared.ClientConfig): nur Sichtbares.
-- Texte, uiTokens, assetStyles, rarityStyles, lighting, effects und Anzeige-Daten zu Items, Zonen und Upgrades.
-- Nie hier: Preise, Spawn-Gewichte, products, passes, remotes, sim. Die volle Config baut server/ServerConfig.luau.
-- Seltenheiten als Materialvarianten (games/junkyard_magnet/art/STYLE.md): rusty = common, chrome = rare,
-- gold = epic, neon = legendary. Asset-Schluessel = FBX-Namen in art/export (z. B. item_gear_gold).
-- Farben aus der Palette in STYLE.md. Keine Asset-IDs: Items sind Bauteile nach den Blender-Formen (ItemShapes).

local ItemShapes = require(script.Parent:WaitForChild("ItemShapes"))

local PALETTE = {
	rust_dark = Color3.fromHex("#8A3B1E"),
	rust_orange = Color3.fromHex("#E0702E"),
	chrome_light = Color3.fromHex("#DCE6F0"),
	chrome_dark = Color3.fromHex("#7D8B99"),
	gold = Color3.fromHex("#FFC21A"),
	gold_deep = Color3.fromHex("#C9800C"),
	neon_cyan = Color3.fromHex("#2BF5E3"),
	neon_pink = Color3.fromHex("#FF45D6"),
	magnet_red = Color3.fromHex("#E8322F"),
	steel_blue = Color3.fromHex("#3F72A8"),
	olive_green = Color3.fromHex("#7A9E3E"),
	sand = Color3.fromHex("#D9B98A"),
}

local RARITY_OF = { rusty = "common", chrome = "rare", gold = "epic", neon = "legendary" }
local RARITY_COLOR = {
	rusty = PALETTE.rust_orange,
	chrome = PALETTE.chrome_light,
	gold = PALETTE.gold,
	neon = PALETTE.neon_cyan,
}
-- Form und Groesse (Studs) je Schrottteil, solange es keine Meshes gibt.
local SHAPE_STYLE = {
	plate = { shape = "Block", size = 1.4 },
	pipe = { shape = "Cylinder", size = 1.5 },
	gear = { shape = "Cylinder", size = 1.8 },
	bolt = { shape = "Block", size = 1.2 },
	barrel = { shape = "Cylinder", size = 1.7 },
}

-- Zone -> { { Form, Variante } }: gewoehnliche Teile plus je eine seltene, epische und legendaere Stufe.
local ZONE_ITEMS = {
	zone_a = {
		{ "plate", "rusty" },
		{ "bolt", "rusty" },
		{ "bolt", "chrome" },
		{ "gear", "gold" },
		{ "barrel", "neon" },
	},
	zone_b = {
		{ "pipe", "rusty" },
		{ "barrel", "rusty" },
		{ "pipe", "chrome" },
		{ "plate", "gold" },
		{ "gear", "neon" },
	},
	zone_c = {
		{ "gear", "rusty" },
		{ "plate", "rusty" },
		{ "barrel", "chrome" },
		{ "bolt", "gold" },
		{ "pipe", "neon" },
	},
}

local items = {}
local assetStyles = {}
for zoneId, list in ZONE_ITEMS do
	for _, entry in list do
		local shape, variant = entry[1], entry[2]
		local asset = "item_" .. shape .. "_" .. variant
		items[zoneId .. "_" .. shape .. "_" .. variant] = {
			zoneId = zoneId,
			asset = asset,
			nameKey = "item_" .. shape .. "_" .. variant .. "_name",
			rarity = RARITY_OF[variant],
		}
		-- Bauteile aus den Blender-Formen (art/scripts/jm_roblox.py); shape/size bleiben als Rueckfall.
		local built = (ItemShapes :: any)[asset]
		assetStyles[asset] = {
			shape = SHAPE_STYLE[shape].shape,
			size = if built then built.size else SHAPE_STYLE[shape].size,
			color = RARITY_COLOR[variant],
			parts = if built then built.parts else nil,
			height = if built then built.height else nil,
		}
	end
end

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

local SHAPE_NAMES = { plate = "Blechplatte", pipe = "Rohrstück", gear = "Zahnrad", bolt = "Schraube", barrel = "Fass" }
local VARIANT_NAMES = { rusty = "Rostige", chrome = "Chrom-", gold = "Gold-", neon = "Neon-" }

local texts = {
	rarity_common = "Gewöhnlich",
	rarity_rare = "Selten",
	rarity_epic = "Episch",
	rarity_legendary = "Legendär",
	zone_a_name = "Schrottfeld",
	zone_b_name = "Autofriedhof",
	zone_c_name = "Kranplatz",
	upgrade_range_name = "Magnet-Reichweite",
	upgrade_capacity_name = "Ladefläche",
	upgrade_sell_bonus_name = "Händlerbonus",
	hud_coins = "Münzen: {coins}",
	hud_inventory = "Ladung: {count} / {capacity}",
	hud_full = "(voll)",
	hud_level = "Stufe {level}/{maxLevel}",
	hud_cost = "{cost} Münzen",
	hud_max = "MAX",
	hud_zone_purchase = "{zone}: {cost} Münzen",
	hud_zone_level = "{zone}: {upgrade} Stufe {level}",
	hud_zone_coins = "{zone}: ab {amount} Münzen",
	hud_zone_all = "Alle Bereiche frei",
	hud_unlock = "Freischalten",
	hud_collect = "Magnet",
	hud_sell = "Verkauf",
	hud_upgrades = "Upgrades",
	hint_full = "Ladefläche voll! Folge dem Strahl zur Waage.",
	onboarding_collect = "Lauf zum Schrott und zieh ihn mit dem Magneten an.",
	onboarding_sell = "Bring die Ladung zur Waage und verkaufe sie.",
	onboarding_upgrade = "Kauf ein Upgrade.",
	onboarding_unlock = "Schalte den Autofriedhof frei.",
	feedback_collected = "+{count}",
	feedback_earned = "+{coins} Münzen",
	feedback_upgraded = "Upgrade: {upgrade}",
	feedback_unlocked = "Neu frei: {zone}",
	feedback_full = "Ladefläche voll!",
	feedback_found = "{rarity}! {item}",
	leaderstats_coins = "Münzen",
	leaderstats_zone = "Bereich",
	sign_sell = "WAAGE",
	system_load_failed = "Dein Spielstand konnte gerade nicht geladen werden. Bitte gleich erneut beitreten.",
}
for shape, shapeName in SHAPE_NAMES do
	for variant, variantName in VARIANT_NAMES do
		local separator = if string.sub(variantName, -1) == "-" then "" else " "
		texts["item_" .. shape .. "_" .. variant .. "_name"] = variantName .. separator .. shapeName
	end
end

-- Sichtbarkeit aus 15-20 m: jedes Teil schwebt und dreht sich; ab chrome Umriss und Funkeln, gold und neon
-- zusaetzlich Lichtschein (Kit-Deckel fuer Lichter und Funkeln gilt weiter).
local rarityStyles = {
	common = { bob = 0.35, spin = 50 },
	rare = { bob = 0.4, spin = 70, highlight = true, sparkles = true, accent = PALETTE.chrome_light },
	-- Lichtschein etwa halbiert gegenueber dem Kit-Standard (2/3), damit nichts ueberstrahlt.
	epic = {
		bob = 0.45,
		spin = 80,
		highlight = true,
		sparkles = true,
		light = true,
		lightBrightness = 1,
		lightRange = 6,
		accent = PALETTE.gold,
	},
	legendary = {
		bob = 0.5,
		spin = 110,
		highlight = true,
		sparkles = true,
		light = true,
		lightBrightness = 1.5,
		lightRange = 7,
		accent = PALETTE.neon_cyan,
	},
}

-- Warmes, sattes Nachmittagslicht ueber dem Schrottplatz (kit/src/LightingProfile.luau).
local lighting = {
	properties = {
		-- TimeOfDay statt ClockTime: ClockTime ist laut Doku NotReplicated.
		TimeOfDay = "15:30:00",
		Brightness = 2.8,
		Ambient = Color3.fromRGB(95, 85, 80),
		OutdoorAmbient = Color3.fromRGB(160, 145, 130),
		ColorShift_Top = Color3.fromRGB(255, 225, 190),
		ColorShift_Bottom = Color3.fromRGB(150, 170, 220),
		EnvironmentDiffuseScale = 0.6,
		EnvironmentSpecularScale = 0.9,
		GlobalShadows = true,
		ExposureCompensation = 0.1,
	},
	-- Leichter warmer Dunst: nah klar, zum Horizont weich auslaufend (Fabrik-Silhouette nur noch als Schemen).
	atmosphere = {
		Density = 0.28,
		Offset = 0.12,
		Color = Color3.fromRGB(232, 206, 168),
		Decay = Color3.fromRGB(190, 145, 105),
		Glare = 0.25,
		Haze = 1.4,
	},
	colorCorrection = {
		Brightness = 0.02,
		Contrast = 0.12,
		Saturation = 0.25,
		TintColor = Color3.fromRGB(255, 248, 235),
	},
	-- Bloom halbiert: Neon und Gold sollen leuchten, aber nicht ueberstrahlen.
	bloom = { Intensity = 0.35, Size = 22, Threshold = 1.2 },
	sunRays = { Intensity = 0.08, Spread = 0.7 },
	sky = { SunAngularSize = 16, CelestialBodiesShown = true },
}

local effects = {
	collected = { textKey = "feedback_collected", color = Color3.fromRGB(255, 255, 255) },
	earned = { textKey = "feedback_earned", color = PALETTE.gold },
	upgraded = { textKey = "feedback_upgraded", color = PALETTE.chrome_light },
	unlocked = { textKey = "feedback_unlocked", color = PALETTE.olive_green },
	full = { textKey = "feedback_full", color = PALETTE.magnet_red },
	found = { textKey = "feedback_found", color = PALETTE.neon_pink },
	-- Nur kostenlose Sounds des Erstellers "Roblox" aus dem Creator Store. Fuer Einsammeln, Upgrade, Freischalten
	-- und seltenen Fund fand sich kein eindeutig passender Roblox-Sound; diese bleiben bewusst leer.
	sounds = {
		earned = "rbxassetid://127645268874265", -- CoinTransfer_01 (Roblox): Verkaufen
	},
}

local uiTokens = {
	background = Color3.fromRGB(40, 28, 22),
	panel = Color3.fromRGB(70, 42, 28),
	text = Color3.fromRGB(255, 245, 230),
	accent = PALETTE.rust_orange,
	disabled = Color3.fromRGB(110, 100, 95),
	highlight = PALETTE.gold,
	highlightText = Color3.fromRGB(45, 30, 15),
	font = Enum.Font.GothamBlack,
	textSize = 22,
	padding = 12,
}

return {
	palette = PALETTE,
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
