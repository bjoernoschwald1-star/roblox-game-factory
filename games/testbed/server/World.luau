--!strict
-- Baut die Testbed-Welt nach der Welt-Konvention des Cores, falls sie noch nicht existiert:
--   <parent>.FactoryWorld.Floor            grauer Boden
--   <parent>.FactoryWorld.Zones.<zoneId>   je eine Plattform pro Zone, nach order nebeneinander mit Abstand
--   <parent>.FactoryWorld.SellAreas.SellArea  Verkaufs-Volumen (halbtransparent, ohne Kollision)
--   <parent>.FactoryWorld.SellPad          sichtbare Markierung unter dem Verkaufs-Volumen
--   <parent>.FactoryWorld.Spawn            SpawnLocation am Start
-- Nur einfache, verankerte Parts; keine Unions oder PartOperations, keine Assets.

local World = {}

World.ROOT_NAME = "FactoryWorld"

local ZONE_SIZE = Vector3.new(44, 1, 44)
local ZONE_GAP = 16
local FLOOR_TOP = 0

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
		Color3.fromRGB(110, 110, 110),
		root
	)

	local zones = Instance.new("Folder")
	zones.Name = "Zones"
	zones.Parent = root
	local shades = { Color3.fromRGB(160, 160, 160), Color3.fromRGB(140, 140, 150), Color3.fromRGB(125, 135, 125) }
	for index, zoneId in zoneIds do
		local x = (index - 1) * (ZONE_SIZE.X + ZONE_GAP) + ZONE_SIZE.X / 2
		part(
			zoneId,
			ZONE_SIZE,
			Vector3.new(x, FLOOR_TOP + ZONE_SIZE.Y / 2, 0),
			shades[(index - 1) % #shades + 1],
			zones
		)
	end

	-- Verkaufsflaeche und Spawn vor der ersten Zone.
	local sellAreas = Instance.new("Folder")
	sellAreas.Name = "SellAreas"
	sellAreas.Parent = root
	local sellCenter = Vector3.new(ZONE_SIZE.X / 2, FLOOR_TOP, -ZONE_SIZE.Z / 2 - 22)
	local sellArea = part(
		"SellArea",
		Vector3.new(14, 10, 14),
		sellCenter + Vector3.new(0, 5, 0),
		Color3.fromRGB(90, 160, 90),
		sellAreas
	)
	sellArea.Transparency = 0.75
	sellArea.CanCollide = false
	sellArea.CanTouch = false
	part("SellPad", Vector3.new(14, 0.2, 14), sellCenter + Vector3.new(0, 0.1, 0), Color3.fromRGB(70, 140, 70), root)

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Position = Vector3.new(ZONE_SIZE.X / 2 + 20, FLOOR_TOP + 0.5, -ZONE_SIZE.Z / 2 - 22)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root

	root.Parent = container
	return root
end

return World
