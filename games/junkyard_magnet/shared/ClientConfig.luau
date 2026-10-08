--!strict
-- Client-Teil der Junkyard-Magnet-Config (ReplicatedStorage.JunkyardShared.ClientConfig): nur Sichtbares.
-- Texte je Sprache (textsByLanguage de/en, texts = Standardsprache), uiTokens, assetStyles, rarityStyles, lighting,
-- effects und Anzeige-Daten zu Items, Zonen und Upgrades.
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
	anchor = { shape = "Block", size = 1.6 },
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
		{ "plate", "chrome" },
	},
	zone_c = {
		{ "gear", "rusty" },
		{ "plate", "rusty" },
		{ "barrel", "chrome" },
		{ "bolt", "gold" },
		{ "pipe", "neon" },
		{ "pipe", "gold" },
		{ "barrel", "gold" },
	},
	-- Hafen: wertvollere bekannte Formen plus der Anker in allen vier Seltenheiten.
	zone_d = {
		{ "barrel", "rusty" },
		{ "anchor", "rusty" },
		{ "gear", "chrome" },
		{ "anchor", "chrome" },
		{ "anchor", "gold" },
		{ "anchor", "neon" },
		{ "plate", "neon" },
		{ "bolt", "neon" },
	},
}

-- Sammelalbum: je Form eine Reihe mit den vier Seltenheiten (24 Eintraege); Eintrag = Asset-Schluessel, umfasst alle
-- Itemtypen dieser Form und Seltenheit (z. B. rostige Fass in Autofriedhof und Hafen). Jede Kombination kommt in
-- mindestens einer Zone vor. Belohnungen stehen in server/ServerConfig.luau.
local ALBUM_SHAPES = { "plate", "pipe", "gear", "bolt", "barrel", "anchor" }
local ALBUM_VARIANTS = { "rusty", "chrome", "gold", "neon" }

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

-- Album-Anzeige (kit AlbumModel) und Gruppen-Aufbau fuer die Server-Config: groups[groupId] = { order, nameKey,
-- entries = { { id, itemTypes } } }.
local albumDisplay = { groups = {}, entries = {} }
local albumGroups = {}
for order, shape in ALBUM_SHAPES do
	local groupId = "album_" .. shape
	local entries = {}
	for _, variant in ALBUM_VARIANTS do
		local asset = "item_" .. shape .. "_" .. variant
		local itemTypes = {}
		for itemId, item in items do
			if item.asset == asset then
				table.insert(itemTypes, itemId)
			end
		end
		table.sort(itemTypes)
		table.insert(entries, { id = asset, itemTypes = itemTypes })
		albumDisplay.entries[asset] = { nameKey = asset .. "_name", rarity = RARITY_OF[variant] }
	end
	albumGroups[groupId] = { order = order, nameKey = groupId .. "_name", entries = entries }
	albumDisplay.groups[groupId] = groupId .. "_name"
end

local zones = {
	zone_a = { order = 1, nameKey = "zone_a_name", condition = { type = "always" } },
	zone_b = { order = 2, nameKey = "zone_b_name", condition = { type = "purchase", cost = 150 } },
	zone_c = {
		order = 3,
		nameKey = "zone_c_name",
		condition = { type = "upgradeLevel", dimension = "capacity", level = 3 },
	},
	zone_d = { order = 4, nameKey = "zone_d_name", condition = { type = "purchase", cost = 39000 } },
}

local upgrades = {
	range = { nameKey = "upgrade_range_name" },
	capacity = { nameKey = "upgrade_capacity_name" },
	sell_bonus = { nameKey = "upgrade_sell_bonus_name" },
}

local SHAPE_NAMES = {
	plate = "Blechplatte",
	pipe = "Rohrstück",
	gear = "Zahnrad",
	bolt = "Schraube",
	barrel = "Fass",
	anchor = "Anker",
}
local VARIANT_NAMES = { rusty = "Rostig", chrome = "Chrom-", gold = "Gold-", neon = "Neon-" }
-- Endung von "Rostig" nach Genus der Form (die Blechplatte, das Rohrstueck, der Anker).
local RUSTY_ENDING = { plate = "e", pipe = "es", gear = "es", bolt = "e", barrel = "es", anchor = "er" }

local textsDe = {
	rarity_common = "Gewöhnlich",
	rarity_rare = "Selten",
	rarity_epic = "Episch",
	rarity_legendary = "Legendär",
	zone_a_name = "Schrottfeld",
	zone_b_name = "Autofriedhof",
	zone_c_name = "Kranplatz",
	zone_d_name = "Hafen",
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
	-- Schmelze (Prestige im Kern): ab der Schwelle Neustart gegen dauerhaften Verkaufsmultiplikator.
	hud_prestige = "Schmelze",
	prestige_title = "Alles einschmelzen?",
	prestige_lose = "Du verlierst: alle Münzen, Upgrades und Bereiche.",
	prestige_gain = "Du bekommst dauerhaft ×{multiplier} auf jeden Verkauf.",
	prestige_confirm = "Einschmelzen",
	prestige_cancel = "Abbrechen",
	hud_album = "Album",
	album_title = "Sammelalbum",
	album_progress = "{found} / {total}",
	album_row_progress = "{found}/{total}",
	album_reward_coins = "+{coins} Münzen",
	album_reward_bonus = "+{percent} % Verkauf",
	album_reward_done = "✓",
	album_plate_name = "Blechplatten",
	album_pipe_name = "Rohre",
	album_gear_name = "Zahnräder",
	album_bolt_name = "Schrauben",
	album_barrel_name = "Fässer",
	album_anchor_name = "Anker",
	feedback_album_new = "Neu im Album! {item}",
	feedback_album_complete = "Reihe komplett: {group}!",
	feedback_prestiged = "Eingeschmolzen! Verkauf ×{multiplier}",
	decimal_separator = ",",
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
		local prefix = if variant == "rusty" then variantName .. RUSTY_ENDING[shape] .. " " else variantName
		textsDe["item_" .. shape .. "_" .. variant .. "_name"] = prefix .. shapeName
	end
end

-- Englischer Textsatz: gleiche Schluessel wie textsDe (Test 152 prueft das), kurz und kindgerecht.
local textsEn = {
	rarity_common = "Common",
	rarity_rare = "Rare",
	rarity_epic = "Epic",
	rarity_legendary = "Legendary",
	zone_a_name = "Scrap Field",
	zone_b_name = "Car Graveyard",
	zone_c_name = "Crane Yard",
	zone_d_name = "Harbor",
	upgrade_range_name = "Magnet Range",
	upgrade_capacity_name = "Cargo Space",
	upgrade_sell_bonus_name = "Dealer Bonus",
	hud_coins = "Coins: {coins}",
	hud_inventory = "Cargo: {count} / {capacity}",
	hud_full = "(full)",
	hud_level = "Level {level}/{maxLevel}",
	hud_cost = "{cost} coins",
	hud_max = "MAX",
	hud_zone_purchase = "{zone}: {cost} coins",
	hud_zone_level = "{zone}: {upgrade} level {level}",
	hud_zone_coins = "{zone}: from {amount} coins",
	hud_zone_all = "All areas unlocked",
	hud_unlock = "Unlock",
	hud_collect = "Magnet",
	hud_sell = "Sell",
	hud_upgrades = "Upgrades",
	hud_prestige = "Melt",
	prestige_title = "Melt everything down?",
	prestige_lose = "You lose: all coins, upgrades and areas.",
	prestige_gain = "You get ×{multiplier} on every sale, forever.",
	prestige_confirm = "Melt down",
	prestige_cancel = "Cancel",
	hud_album = "Album",
	album_title = "Collection",
	album_progress = "{found} / {total}",
	album_row_progress = "{found}/{total}",
	album_reward_coins = "+{coins} coins",
	album_reward_bonus = "+{percent}% sales",
	album_reward_done = "✓",
	album_plate_name = "Plates",
	album_pipe_name = "Pipes",
	album_gear_name = "Gears",
	album_bolt_name = "Bolts",
	album_barrel_name = "Barrels",
	album_anchor_name = "Anchors",
	feedback_album_new = "New in your album! {item}",
	feedback_album_complete = "Row complete: {group}!",
	feedback_prestiged = "Melted down! Sales ×{multiplier}",
	decimal_separator = ".",
	hint_full = "Cargo full! Follow the beam to the scale.",
	onboarding_collect = "Run to the scrap and pull it in with your magnet.",
	onboarding_sell = "Take your cargo to the scale and sell it.",
	onboarding_upgrade = "Buy an upgrade.",
	onboarding_unlock = "Unlock the Car Graveyard.",
	feedback_collected = "+{count}",
	feedback_earned = "+{coins} coins",
	feedback_upgraded = "Upgrade: {upgrade}",
	feedback_unlocked = "Unlocked: {zone}",
	feedback_full = "Cargo full!",
	feedback_found = "{rarity}! {item}",
	leaderstats_coins = "Coins",
	leaderstats_zone = "Area",
	sign_sell = "SCALE",
	system_load_failed = "Your progress could not be loaded right now. Please rejoin in a moment.",
}
local SHAPE_NAMES_EN = {
	plate = "Plate",
	pipe = "Pipe",
	gear = "Gear",
	bolt = "Bolt",
	barrel = "Barrel",
	anchor = "Anchor",
}
local VARIANT_NAMES_EN = { rusty = "Rusty", chrome = "Chrome", gold = "Gold", neon = "Neon" }
for shape, shapeName in SHAPE_NAMES_EN do
	for variant, variantName in VARIANT_NAMES_EN do
		textsEn["item_" .. shape .. "_" .. variant .. "_name"] = variantName .. " " .. shapeName
	end
end

-- Sprachen: Der Client waehlt nach der Spieler-Locale (kit/src/Locale.luau; de-* -> de, sonst en). Was alle Spieler
-- gemeinsam sehen und der Server setzt (Rangliste, Kick-Text), nutzt DEFAULT_LANGUAGE; Schilder in der Welt
-- uebersetzt jeder Client lokal (Attribut textKey am Schild).
local DEFAULT_LANGUAGE = "en"
local textsByLanguage = { de = textsDe, en = textsEn }
local texts = textsByLanguage[DEFAULT_LANGUAGE]

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
	prestiged = { textKey = "feedback_prestiged", color = PALETTE.rust_orange },
	albumNew = { textKey = "feedback_album_new", color = PALETTE.neon_cyan },
	albumCompleted = { textKey = "feedback_album_complete", color = PALETTE.gold },
	-- Nur kostenlose Sounds des Erstellers "Roblox" aus dem Creator Store (im Spieltest geladen, Laenge in Sekunden).
	sounds = {
		collected = "rbxassetid://12221990", -- electronicpingshort.wav (Roblox), 0,46 s: Einsammeln
		earned = "rbxassetid://127645268874265", -- CoinTransfer_01 (Roblox), 1,66 s: Verkaufen
		upgraded = "rbxassetid://10066947742", -- RBLX UI Purchase (SFX) (Roblox), 0,87 s: Upgrade gekauft
		unlocked = "rbxassetid://12222253", -- victory.wav (Roblox), 1,21 s: Zone freigeschaltet
		found = "rbxassetid://15675043410", -- Roblox_UI_Tonal_Stinger (Roblox), 1,47 s: seltener Fund
		prestiged = "rbxassetid://15675024286", -- Roblox_UI_Whoosh_01 (Roblox): Schmelze
		albumNew = "rbxassetid://15675059323", -- Roblox_UI_Bright_Click (Roblox), 0,37 s: neu im Album
		albumCompleted = "rbxassetid://12222253", -- victory.wav (Roblox), 1,21 s: Album-Reihe komplett
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
	album = albumDisplay,
	albumGroups = albumGroups,
	texts = texts,
	textsByLanguage = textsByLanguage,
	defaultLanguage = DEFAULT_LANGUAGE,
	assetStyles = assetStyles,
	rarityStyles = rarityStyles,
	lighting = lighting,
	effects = effects,
	uiTokens = uiTokens,
	onboardingSteps = nil,
}
