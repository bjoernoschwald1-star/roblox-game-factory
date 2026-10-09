--!strict
-- Probe-Raum Game #002 (Forschungsstation, Vorlage build/art/konzept-002/station.png): Licht, Masse, Wandfolge,
-- Deko und Effekte als Daten fuer Server (Aufbau) und Client (Flackern, Drohne, Funken, Bildschirme). Nur Optik,
-- keine Spielregeln. Lichttechnik steht in game002-probe.project.json (LightingStyle Realistic,
-- PrioritizeLightingQuality, Technology Future), weil Technology fuer Skripte nicht schreibbar ist.
-- Look-Runde 2: Grundlicht fast aus, Lichtinseln (2 enge Deckenkegel mit sichtbarem Lichtkegel, rotes Notlicht an
-- der Westwand, Artefakt, schwache Bildschirme), dunkler Dunst, der den Gang in der Tiefe verschluckt; Lesbarkeit
-- ueber Leuchtakzente (Tuerrahmen, Bodenmarken im Gang) und Warnstreifen.
-- Offene Punkte: Handy-Leistung nur am echten Geraet messbar (privater Test-Ort).

local ProbeConfig = {}

ProbeConfig.FOLDER_NAME = "Game002Probe"
-- Attribut, ueber das der Client die Effekt-Instanzen findet ("flicker", "drone", "sparks", "pulse", "screen")
ProbeConfig.EFFECT_ATTRIBUTE = "probeEffect"

ProbeConfig.room = {
	size = 24, -- Innenmass in Studs (3 x 3 Module zu 8 Studs)
	module = 8,
	corridorModules = 2, -- Gangstueck hinter der Tuer (Nordwand)
	floorTop = 0.67,
	wallHeight = 12,
}

-- Wandfolge je Seite, Reihenfolge entlang steigender Koordinate (Nord/Sued: x = -8, 0, 8; Ost/West: z = -8, 0, 8;
-- Gang: z = -16, -24). Varianten: panel, window, damaged; "door" nur in der Nordmitte. Keine zwei gleichen Paneele
-- nebeneinander, auch nicht ueber Ecken.
ProbeConfig.walls = {
	north = { "damaged", "door", "panel" },
	east = { "window", "panel", "damaged" },
	south = { "panel", "window", "panel" },
	west = { "window", "panel", "damaged" },
	corridorWest = { "panel", "damaged" },
	corridorEast = { "damaged", "panel" },
	corridorEnd = { "panel" },
}

ProbeConfig.lighting = {
	properties = {
		-- Runde 3: zwischen Runde 1 (Ambient 18, 22, 28, buero-hell) und Runde 2 (2, 3, 4, Raumhaelften schwarz).
		-- Schwaches kuehles Grundlicht, damit Waende, Boden und Wege ueberall schemenhaft sichtbar bleiben; die
		-- Spiegelung des Nachthimmels bleibt aus (sie faerbte in Runde 2 alles gleichmaessig blaugrau).
		Ambient = Color3.fromRGB(16, 20, 26),
		OutdoorAmbient = Color3.fromRGB(10, 12, 16),
		Brightness = 0,
		ClockTime = 0,
		EnvironmentDiffuseScale = 0.08,
		EnvironmentSpecularScale = 0,
		GlobalShadows = true,
		ExposureCompensation = 0.15,
		ShadowSoftness = 0.2,
	},
	atmosphere = {
		-- dunkler Dunst: Farbe nahe Schwarz, sonst wirkt er im kleinen Raum wie heller Nebel (Runde 1)
		Density = 0.4,
		Offset = 0,
		Color = Color3.fromRGB(12, 14, 18),
		Decay = Color3.fromRGB(4, 5, 7),
		Glare = 0,
		Haze = 1.4,
	},
	colorCorrection = {
		Brightness = 0,
		Contrast = 0.3,
		Saturation = -0.15,
		TintColor = Color3.fromRGB(212, 230, 255),
	},
	bloom = {
		Intensity = 1,
		Size = 30,
		Threshold = 1.2,
	},
}

ProbeConfig.lights = {
	ceiling = {
		color = Color3.fromRGB(205, 228, 255),
		-- eng und nicht zu hell: im Stil Realistic streut die Deckenleuchte sonst bis in die Ecken (Spieltest)
		brightness = 3.8,
		range = 16,
		angle = 42,
		-- sichtbarer Lichtkegel (Beam) unter der Leuchte
		coneTop = 2.4,
		coneBottom = 9,
		coneTransparency = 0.84,
		-- Flackern: meistens an, gelegentlich kurze Aussetzer (Sekunden)
		steadyMin = 1.2,
		steadyMax = 4.5,
		dropouts = 3,
		dropoutMin = 0.04,
		dropoutMax = 0.12,
	},
	emergency = {
		color = Color3.fromRGB(255, 40, 25),
		-- Lichtinsel statt Flutlicht: bei groesserer Reichweite faerbt der Puls die ganze Suedwest-Ecke rot
		brightness = 1.3,
		range = 10,
		pulseSeconds = 1.6,
		height = 9.6, -- ueber dem Boden, an der Westwand (z = 0)
	},
	artifact = {
		color = Color3.fromRGB(40, 255, 205),
		-- kleine Reichweite: sonst faerbt es die ganze Suedwest-Ecke tuerkis (Spieltest Runde 2)
		brightness = 1,
		range = 7,
	},
	screen = {
		-- Runde 3: echtes Leuchten ueber eine SurfaceGui (Verlauf und Scanlinien aus Frames, kein Text) statt
		-- flacher Neon-Flaeche; dazu schwaches tuerkises Licht auf Konsole und Boden
		color = Color3.fromRGB(60, 190, 200),
		glowTop = Color3.fromRGB(40, 150, 165),
		glowBottom = Color3.fromRGB(10, 60, 72),
		guiBrightness = 2.2,
		pixelsPerStud = 60,
		scanlines = 24,
		scanlineTransparency = 0.82,
		brightness = 1.1,
		range = 11,
		angle = 120,
		-- leichtes Flackern: Helligkeits-Tween in zufaelligen Abstaenden (Anteil, um den gedimmt wird)
		flickerMin = 0.08,
		flickerMax = 0.3,
		pauseMin = 0.4,
		pauseMax = 2.5,
	},
	-- sehr schwache kuehle Fuelllichter ohne Schatten (Raummitte hoch, Gang), damit kein Bereich reines Schwarz ist
	fill = {
		color = Color3.fromRGB(120, 150, 190),
		points = {
			{ position = Vector3.new(0, 9, 0), brightness = 0.3, range = 22 },
			{ position = Vector3.new(0, 8, -20), brightness = 0.35, range = 16 },
		},
	},
	sideRoom = {
		-- schwaches Licht im Nebenraum hinter den Fenstern (ohne Schatten), damit Tiefe erkennbar ist
		color = Color3.fromRGB(40, 90, 140),
		brightness = 0.35,
		range = 9,
		depth = 6,
	},
	drone = {
		color = Color3.fromRGB(255, 55, 40),
		brightness = 6,
		range = 26,
		angle = 34,
		hoverHeight = 7.5,
		bobAmplitude = 0.6,
		bobSeconds = 2.6,
		sweepDegrees = 35,
		sweepSeconds = 7,
	},
}

-- Testschalter fuer spaetere Handy-Tests bei Tageslicht: hellere Grundwerte, standardmaessig aus
ProbeConfig.BRIGHT_TEST = false
ProbeConfig.brightOverrides = {
	Ambient = Color3.fromRGB(30, 36, 46),
	OutdoorAmbient = Color3.fromRGB(20, 24, 30),
	EnvironmentDiffuseScale = 0.25,
	ExposureCompensation = 0.6,
}
if ProbeConfig.BRIGHT_TEST then
	for name, value in ProbeConfig.brightOverrides do
		ProbeConfig.lighting.properties[name] = value
	end
end

-- Leuchtakzente fuer die Lesbarkeit im Dunkeln (Neon, ohne Lichtquelle)
ProbeConfig.accents = {
	doorFrame = Color3.fromRGB(190, 100, 18),
	doorBeacon = Color3.fromRGB(220, 100, 15),
	guide = Color3.fromRGB(190, 95, 18),
	guideSpacing = 2,
	glass = Color3.fromRGB(30, 50, 60),
	glassTransparency = 0.55,
}

-- Deko-Platzierung: Wand (Seite und Index wie walls), along = Versatz entlang der Wand, height = Mitte ueber Boden
ProbeConfig.decor = {
	vents = {
		{ wall = "north", slot = 3, along = -1.8, height = 7.4 },
		{ wall = "corridorEast", slot = 2, along = 1.5, height = 3 },
		{ wall = "south", slot = 3, along = 1.8, height = 7.4 },
	},
	signs = {
		{ wall = "east", slot = 2, along = -2.2, height = 7.6 },
		{ wall = "corridorEnd", slot = 1, along = 0, height = 7 },
		{ wall = "north", slot = 3, along = 1.6, height = 4.2 },
	},
	puddles = {
		{ x = 6, z = 9, yaw = 20 },
		{ x = 0.6, z = -21, yaw = -70 },
		{ x = -4.5, z = -5, yaw = 110 },
	},
	-- herabhaengende Kabel als sichtbare RopeConstraint (kein Mesh): Anfang an der Decke, Ende an der Decke
	-- (durchhaengend) oder frei mit Stecker (pendelnd)
	cables = {
		{ from = Vector3.new(-9, 12.5, -4), to = Vector3.new(-5, 12.5, -7), length = 9, thickness = 0.14 },
		{ from = Vector3.new(4, 12.5, 6), to = Vector3.new(9, 12.5, 2), length = 10, thickness = 0.18 },
		{ from = Vector3.new(-2, 12.5, -18), length = 7.5, thickness = 0.12 },
	},
	cableColor = Color3.fromRGB(14, 14, 16),
}

ProbeConfig.effects = {
	dustRate = 8,
	steamRate = 14,
	sparkBurstMin = 6,
	sparkBurstMax = 16,
	sparkPauseMin = 2.5,
	sparkPauseMax = 7,
	-- eingebaute Roblox-Partikeltexturen (keine hochgeladenen Bilder)
	dustTexture = "rbxasset://textures/particles/sparkles_main.dds",
	steamTexture = "rbxasset://textures/particles/smoke_main.dds",
	sparkTexture = "rbxasset://textures/particles/sparkles_main.dds",
}

return ProbeConfig
