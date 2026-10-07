--!strict
-- Baut die Testbed-Welt nach der Welt-Konvention des Cores, falls sie noch nicht existiert:
--   <parent>.FactoryWorld.Floor            heller Boden
--   <parent>.FactoryWorld.Zones.<zoneId>   je eine Plattform pro Zone in eigener, klarer Farbe, nach order
--                                          nebeneinander mit Abstand
--   <parent>.FactoryWorld.SellAreas.SellArea  Verkaufs-Volumen (halbtransparent, ohne Kollision)
--   <parent>.FactoryWorld.SellPad          gut sichtbare Verkaufsflaeche mit leuchtendem Rahmen und Schild
--   <parent>.FactoryWorld.Paths            Wege von der Verkaufsflaeche zu jedem Zonen-Tor
--   <parent>.FactoryWorld.Gates.<zoneId>   Tor mit Schild (Zonenname aus config.texts) vor jeder Zone
--   <parent>.FactoryWorld.Spawn            SpawnLocation am Start
-- Nur einfache, verankerte Parts; Schilder als SurfaceGui mit Text. Keine Unions oder PartOperations, keine Assets.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/SurfaceGui

local World = {}

World.ROOT_NAME = "FactoryWorld"

local ZONE_SIZE = Vector3.new(44, 1, 44)
local ZONE_GAP = 16
local FLOOR_TOP = 0
local SELL_OFFSET = 22 -- Abstand der Verkaufsflaeche vor der Zonenreihe

local FLOOR_COLOR = Color3.fromRGB(235, 220, 180)
local PATH_COLOR = Color3.fromRGB(250, 245, 230)
local SELL_COLOR = Color3.fromRGB(255, 200, 50)
local SELL_RIM_COLOR = Color3.fromRGB(255, 150, 40)
local POST_COLOR = Color3.fromRGB(70, 80, 110)
local SIGN_COLOR = Color3.fromRGB(255, 255, 255)
local ZONE_COLORS = {
	Color3.fromRGB(110, 200, 120),
	Color3.fromRGB(90, 170, 240),
	Color3.fromRGB(180, 120, 230),
	Color3.fromRGB(255, 150, 110),
}

local function part(name: string, size: Vector3, position: Vector3, color: Color3, parent: Instance): Part
	local created = Instance.new("Part")
	created.Name = name
	created.Anchored = true
	created.Size = size
	created.Position = position
	created.Color = color
	created.Material = Enum.Material.SmoothPlastic
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- Schild-Text auf einer Seite eines Parts (Front = -Z, Back = +Z).
local function sign(target: Part, text: string, color: Color3, face: Enum.NormalId)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "Label"
	surface.Face = face
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = text
	label.Parent = surface
	surface.Parent = target
end

local function textFor(config: any, key: string?, fallback: string): string
	local texts = config.texts or {}
	local value = if key ~= nil then texts[key] else nil
	return if type(value) == "string" then value else fallback
end

-- Liefert den Welt-Ordner; legt ihn nur an, wenn er fehlt.
function World.build(config: any, parent: Instance?): Instance
	local container: Instance = parent or workspace
	local existing = container:FindFirstChild(World.ROOT_NAME)
	if existing ~= nil then
		return existing
	end

	local root = Instance.new("Folder")
	root.Name = World.ROOT_NAME

	local zoneIds = {}
	for zoneId in config.zones do
		table.insert(zoneIds, zoneId)
	end
	table.sort(zoneIds, function(a: string, b: string): boolean
		return config.zones[a].order < config.zones[b].order
	end)

	local span = #zoneIds * ZONE_SIZE.X + (#zoneIds - 1) * ZONE_GAP
	part(
		"Floor",
		Vector3.new(span + 120, 1, ZONE_SIZE.Z + 120),
		Vector3.new(span / 2, FLOOR_TOP - 0.5, 0),
		FLOOR_COLOR,
		root
	)

	local zones = Instance.new("Folder")
	zones.Name = "Zones"
	zones.Parent = root
	local gates = Instance.new("Folder")
	gates.Name = "Gates"
	gates.Parent = root
	local paths = Instance.new("Folder")
	paths.Name = "Paths"
	paths.Parent = root

	local sellCenter = Vector3.new(ZONE_SIZE.X / 2, FLOOR_TOP, -ZONE_SIZE.Z / 2 - SELL_OFFSET)
	local frontZ = -ZONE_SIZE.Z / 2
	for index, zoneId in zoneIds do
		local x = (index - 1) * (ZONE_SIZE.X + ZONE_GAP) + ZONE_SIZE.X / 2
		local color = ZONE_COLORS[(index - 1) % #ZONE_COLORS + 1]
		part(zoneId, ZONE_SIZE, Vector3.new(x, FLOOR_TOP + ZONE_SIZE.Y / 2, 0), color, zones)

		-- Tor an der Vorderkante der Zone: zwei Pfosten, Querbalken mit Schild.
		local gate = Instance.new("Folder")
		gate.Name = zoneId
		gate.Parent = gates
		for _, side in { -1, 1 } do
			part(
				"Post",
				Vector3.new(1.5, 11, 1.5),
				Vector3.new(x + side * 8, FLOOR_TOP + 5.5, frontZ - 1),
				POST_COLOR,
				gate
			)
		end
		local beam = part("Sign", Vector3.new(18, 3, 1), Vector3.new(x, FLOOR_TOP + 12, frontZ - 1), color, gate)
		sign(beam, textFor(config, config.zones[zoneId].nameKey, zoneId), SIGN_COLOR, Enum.NormalId.Front)

		-- Weg von der Verkaufsflaeche zum Tor (flach, ohne Kollision, damit nichts haengen bleibt).
		local from = sellCenter
		local to = Vector3.new(x, FLOOR_TOP, frontZ - 1)
		local length = (to - from).Magnitude
		local path =
			part("Path", Vector3.new(5, 0.2, length), (from + to) / 2 + Vector3.new(0, 0.1, 0), PATH_COLOR, paths)
		path.CFrame = CFrame.lookAt((from + to) / 2 + Vector3.new(0, 0.1, 0), to + Vector3.new(0, 0.1, 0))
		path.CanCollide = false
	end

	-- Verkaufsflaeche und Spawn vor der ersten Zone.
	local sellAreas = Instance.new("Folder")
	sellAreas.Name = "SellAreas"
	sellAreas.Parent = root
	local sellArea = part("SellArea", Vector3.new(14, 10, 14), sellCenter + Vector3.new(0, 5, 0), SELL_COLOR, sellAreas)
	sellArea.Transparency = 0.85
	sellArea.CanCollide = false
	sellArea.CanTouch = false
	part("SellPad", Vector3.new(14, 0.3, 14), sellCenter + Vector3.new(0, 0.15, 0), SELL_COLOR, root)
	local rim = Instance.new("Folder")
	rim.Name = "SellRim"
	rim.Parent = root
	for _, edge in
		{
			{ Vector3.new(15, 0.5, 0.8), Vector3.new(0, 0.25, 7.4) },
			{ Vector3.new(15, 0.5, 0.8), Vector3.new(0, 0.25, -7.4) },
			{ Vector3.new(0.8, 0.5, 15), Vector3.new(7.4, 0.25, 0) },
			{ Vector3.new(0.8, 0.5, 15), Vector3.new(-7.4, 0.25, 0) },
		}
	do
		local border = part("Rim", edge[1], sellCenter + edge[2], SELL_RIM_COLOR, rim)
		border.Material = Enum.Material.Neon
		border.CanCollide = false
	end
	local sellSign = part("SellSign", Vector3.new(12, 3, 1), sellCenter + Vector3.new(0, 9, 8), SELL_RIM_COLOR, root)
	-- Schild zeigt zu den Zonen (+Z), von dort kommen die Spieler mit vollem Inventar.
	sign(sellSign, textFor(config, "sign_sell", "SELL"), SIGN_COLOR, Enum.NormalId.Back)
	for _, side in { -1, 1 } do
		part("SellPost", Vector3.new(1, 8, 1), sellCenter + Vector3.new(side * 5.5, 4, 8), POST_COLOR, root)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(ZONE_SIZE.X / 2 + 20, FLOOR_TOP + 0.5, -ZONE_SIZE.Z / 2 - SELL_OFFSET)
	spawn.Color = Color3.fromRGB(255, 255, 255)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root

	root.Parent = container
	return root
end

return World
