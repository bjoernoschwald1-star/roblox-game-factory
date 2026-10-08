--!strict
-- Baut den Schrottplatz von Junkyard Magnet nach der Welt-Konvention des Cores, falls er noch nicht existiert:
--   Workspace.Terrain                            Boden (Ground): Sand weit ueber den Zaun hinaus, Zonenflaechen in
--                                                eigener Bodenart; nur ohne Terrain (parent ~= workspace) eine
--                                                Sandplatte <parent>.FactoryWorld.Floor
--   <parent>.FactoryWorld.Zones.<zoneId>         je eine Schrottflaeche pro Zone (Items erscheinen darauf)
--   <parent>.FactoryWorld.SellAreas.SellArea     Verkaufs-Volumen an der Waage (unsichtbar, ohne Kollision)
--   <parent>.FactoryWorld.Props.*                Kulisse aus den Blender-Objekten (Zaun, Wracks, Reifen, Kran ...)
--   <parent>.FactoryWorld.Signs.<zoneId>         Schild mit Zonenname vor jeder Zone
--   <parent>.FactoryWorld.Spawn                  SpawnLocation an der Waage
--   <parent>.FactoryWorld.Backdrop               Hintergrund ausserhalb des Zauns (Backdrop, World.useBackdrop)
-- Die Zonen-Parts bleiben als begehbare Flaeche (Items liegen auf ihrer Oberseite), sind mit Terrain aber
-- unsichtbar; sichtbar ist die weich berandete Terrain-Flaeche darunter.
-- Kulisse: Grundformen aus server/PropShapes.luau (erzeugt aus den Blender-Skripten, art/scripts/jm_roblox.py) als
-- verankerte Parts - spielbar ohne Mesh-Upload. Keine Unions, keine Asset-IDs.
-- Hochgeladene Modelle (World.useModels, Vorlagen aus MeshModels): Dann zeigt ein MeshPart das Objekt; die
-- Grundformen bleiben unsichtbar als Kollision (CollisionFidelity ist zur Laufzeit nicht setzbar, so bleibt das
-- Spielgefuehl gleich), Akzente (andere Farbe/Material als das Mesh) bleiben sichtbar. Ohne Kollision entfallen die
-- unsichtbaren. Fehlt ein Modell, bleibt die sichtbare Bauteil-Version.
local PropShapes = require(script.Parent:WaitForChild("PropShapes"))
local MeshModels = require(script.Parent:WaitForChild("MeshModels"))
local Ground = require(script.Parent:WaitForChild("Ground"))
local Backdrop = require(script.Parent:WaitForChild("Backdrop"))

local World = {}

World.ROOT_NAME = "FactoryWorld"

local models: { [string]: MeshPart } = {}

local backdrop: { [string]: Model } = {}

-- MeshPart-Vorlagen je Objektname (leer = nur Bauteile).
function World.useModels(templates: { [string]: MeshPart })
	models = templates
end

-- Vorbereitete Hintergrund-Vorlagen (Backdrop.prepare) je Name; leer = kein Hintergrund.
function World.useBackdrop(templates: { [string]: Model })
	backdrop = templates
end

local ZONE_SIZE = Vector3.new(44, 1, 44)
local ZONE_GAP = 16
local SELL_OFFSET = 22
local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Neon = Enum.Material.Neon,
}
local SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Cylinder = Enum.PartType.Cylinder,
	Ball = Enum.PartType.Ball,
}
local ZONE_TINTS = {
	Color3.fromHex("#C9A776"),
	Color3.fromHex("#B89A78"),
	Color3.fromHex("#A88E80"),
}

local function part(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local created = Instance.new("Part")
	created.Name = name
	created.Anchored = true
	created.Size = size
	created.CFrame = cframe
	created.Color = color
	created.Material = Enum.Material.SmoothPlastic
	created.TopSurface = Enum.SurfaceType.Smooth
	created.BottomSurface = Enum.SurfaceType.Smooth
	created.Parent = parent
	return created
end

-- Baut ein Kulissen-Objekt aus PropShapes an pivot (Drehpunkt Mitte unten, Vorderseite +Z).
function World.buildProp(name: string, pivot: CFrame, parent: Instance, collide: boolean?, scale: number?): Model
	local k = scale or 1
	local data = (PropShapes :: any)[name]
	assert(data ~= nil, "World: unknown prop " .. name)
	local model = Instance.new("Model")
	model.Name = name
	local template = models[name]
	local accents: { [number]: boolean } = {}
	if template ~= nil then
		MeshModels.visual(template, data.parts, pivot, k, k).Parent = model
		accents = MeshModels.accents(data.parts)
		for index in accents do
			local accent = MeshModels.accentPart(data.parts[index], pivot, k)
			accent.CanCollide = collide ~= false
			accent.Parent = model
		end
	end
	for index, row in data.parts do
		if template ~= nil and (collide == false or accents[index]) then
			continue
		end
		local created = Instance.new("Part")
		created.Name = row[1] .. index
		created.Shape = SHAPES[row[1]] or Enum.PartType.Block
		created.Size = Vector3.new(math.max(row[2] * k, 0.05), math.max(row[3] * k, 0.05), math.max(row[4] * k, 0.05))
		created.CFrame = pivot
			* CFrame.new(
				row[5] * k,
				row[6] * k,
				row[7] * k,
				row[8],
				row[9],
				row[10],
				row[11],
				row[12],
				row[13],
				row[14],
				row[15],
				row[16]
			)
		created.Color = Color3.fromHex(row[17])
		created.Material = MATERIALS[row[18]] or Enum.Material.SmoothPlastic
		created.Anchored = true
		created.CanCollide = collide ~= false
		created.TopSurface = Enum.SurfaceType.Smooth
		created.BottomSurface = Enum.SurfaceType.Smooth
		if template ~= nil then
			created.Transparency = 1
			created.CastShadow = false
		end
		created.Parent = model
	end
	model.Parent = parent
	return model
end

local function sign(target: Part, text: string)
	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 40
	surface.LightInfluence = 0
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 245, 230)
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = surface
	surface.Parent = target
end

local function textFor(config: any, key: string?, fallback: string): string
	local value = if key ~= nil and config.texts then config.texts[key] else nil
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
	local minX, maxX = -40, span + 40
	local minZ, maxZ = -ZONE_SIZE.Z / 2 - SELL_OFFSET - 30, ZONE_SIZE.Z / 2 + 40
	local useTerrain = container == workspace
	if useTerrain then
		-- Die Baseplate einer Studio-Vorlage laege genau in der Terrain-Oberkante (y 0) und flackerte.
		local baseplate = workspace:FindFirstChild("Baseplate")
		if baseplate ~= nil and baseplate:IsA("BasePart") then
			baseplate:Destroy()
		end
	else
		part(
			"Floor",
			Vector3.new(maxX - minX + 40, 1.2, maxZ - minZ + 40),
			CFrame.new((minX + maxX) / 2, -0.5, (minZ + maxZ) / 2),
			Color3.fromHex("#D9B98A"),
			root
		)
	end
	local zoneAreas: { Ground.ZoneArea } = {}

	local zones = Instance.new("Folder")
	zones.Name = "Zones"
	zones.Parent = root
	local signs = Instance.new("Folder")
	signs.Name = "Signs"
	signs.Parent = root
	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = root
	local frontZ = -ZONE_SIZE.Z / 2
	for index, zoneId in zoneIds do
		local x = (index - 1) * (ZONE_SIZE.X + ZONE_GAP) + ZONE_SIZE.X / 2
		-- Mit Terrain liegt die (unsichtbare) Zonen-Oberseite auf Bodenhoehe y 0, sonst als Platte bei y 1.
		local zoneY = if useTerrain then -ZONE_SIZE.Y / 2 else ZONE_SIZE.Y / 2
		local zonePart =
			part(zoneId, ZONE_SIZE, CFrame.new(x, zoneY, 0), ZONE_TINTS[(index - 1) % #ZONE_TINTS + 1], zones)
		if useTerrain then
			zonePart.Transparency = 1
			zonePart.CastShadow = false
		end
		table.insert(zoneAreas, { center = zonePart.Position, size = zonePart.Size })
		local board =
			part("Board", Vector3.new(14, 3, 0.6), CFrame.new(x, 8, frontZ - 2), Color3.fromHex("#8A3B1E"), signs)
		sign(board, textFor(config, config.zones[zoneId].nameKey, zoneId))
		for _, side in { -1, 1 } do
			part(
				"Post",
				Vector3.new(0.8, 9.5, 0.8),
				CFrame.new(x + side * 6, 4.75, frontZ - 2),
				Color3.fromHex("#3F72A8"),
				signs
			)
		end
	end

	-- Waage mit Verkaufs-Volumen und Spawn daneben.
	local sellCenter = Vector3.new(ZONE_SIZE.X / 2, 0, frontZ - SELL_OFFSET)
	local sellAreas = Instance.new("Folder")
	sellAreas.Name = "SellAreas"
	sellAreas.Parent = root
	local sellArea = part(
		"SellArea",
		Vector3.new(14, 10, 14),
		CFrame.new(sellCenter + Vector3.new(0, 5, 0)),
		Color3.fromHex("#FFC21A"),
		sellAreas
	)
	sellArea.Transparency = 1
	sellArea.CanCollide = false
	sellArea.CanTouch = false
	-- Waagenplattform liegt im Modell 1,75 Studs vor dem Drehpunkt; Bude hinten (-Z, weg von den Zonen).
	World.buildProp("prop_sell_station", CFrame.new(sellCenter + Vector3.new(0, 0, -1.75)), props)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	-- Blick zu den Zonen (+Z).
	spawn.CFrame = CFrame.new(sellCenter + Vector3.new(20, 0.5, 0)) * CFrame.Angles(0, math.pi, 0)
	-- Betonplatte mit Warnstreifen statt der grauen Noppenplatte.
	spawn.Color = Color3.fromHex("#A39E94")
	spawn.Material = Enum.Material.Concrete
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Parent = root
	local stripeA, stripeB = Color3.fromHex("#FFC21A"), Color3.fromHex("#2B2B2E")
	for k = 0, 9 do
		local color = if k % 2 == 0 then stripeA else stripeB
		local along = -4.5 + k
		for _, edge in
			{
				{ Vector3.new(1, 0.1, 0.6), Vector3.new(along, 0.55, -4.7) },
				{ Vector3.new(1, 0.1, 0.6), Vector3.new(along, 0.55, 4.7) },
				{ Vector3.new(0.6, 0.1, 1), Vector3.new(-4.7, 0.55, along) },
				{ Vector3.new(0.6, 0.1, 1), Vector3.new(4.7, 0.55, along) },
			}
		do
			local stripe = part("SpawnStripe", edge[1], spawn.CFrame * CFrame.new(edge[2]), color, root)
			stripe.CanCollide = false
		end
	end

	-- Boden: wenige kleine, dunkle Oelflecken (glaenzend, fast schwarz - nicht rot) und Fahrspuren von der Waage
	-- zu den Zonen. Flache Parts ohne Kollision knapp ueber dem Boden.
	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = root
	local trackColor = Color3.fromHex("#D9B98A"):Lerp(Color3.new(0, 0, 0), 0.18)
	local function track(from: Vector3, to: Vector3)
		local direction = (to - from)
		local side = direction.Unit:Cross(Vector3.yAxis) * 1.6
		for _, offset in { side, -side } do
			local center = (from + to) / 2 + offset + Vector3.new(0, 0.12, 0)
			local strip = part(
				"Track",
				Vector3.new(0.7, 0.04, direction.Magnitude),
				CFrame.lookAt(center, center + direction),
				trackColor,
				ground
			)
			strip.CanCollide = false
		end
	end
	for index in zoneIds do
		local x = (index - 1) * (ZONE_SIZE.X + ZONE_GAP) + ZONE_SIZE.X / 2
		track(sellCenter + Vector3.new(0, 0, 8), Vector3.new(x, 0, frontZ - 4))
	end
	track(Vector3.new(minX + 10, 0, sellCenter.Z - 12), Vector3.new(maxX - 10, 0, sellCenter.Z - 12))
	local rng = Random.new(7)
	local oil = Color3.fromHex("#26221F")
	for _ = 1, 12 do
		local x = rng:NextNumber(minX + 10, maxX - 10)
		local z = rng:NextNumber(minZ + 8, frontZ - 4)
		local diameter = rng:NextNumber(1.2, 2.6)
		local spot = part(
			"Oil",
			Vector3.new(0.05, diameter, diameter * rng:NextNumber(0.6, 1)),
			CFrame.new(x, 0.13, z) * CFrame.Angles(0, rng:NextNumber(0, math.pi), math.pi / 2),
			oil,
			ground
		)
		spot.Shape = Enum.PartType.Cylinder
		spot.Reflectance = 0.15
		spot.CanCollide = false
	end

	-- Kulisse (dicht): Kran als Wahrzeichen, grosse Schrotthaufen, Container-Reihen (teils gestapelt), gestapelte
	-- Wracks, Reifenstapel und Sandhuegel mit Rampen. Hoehen: Container 8,5, Wrack etwa 5,2 Studs (PropShapes.size).
	local sizes = PropShapes :: any
	local function place(name: string, x: number, z: number, degrees: number, y: number?, scale: number?)
		World.buildProp(name, CFrame.new(x, y or 0, z) * CFrame.Angles(0, math.rad(degrees), 0), props, nil, scale)
	end
	local function stackedWrecks(x: number, z: number, degrees: number)
		place("prop_car_wreck", x, z, degrees)
		place("prop_car_wreck", x + 0.8, z - 0.6, degrees + 14, sizes.prop_car_wreck.size[2] - 0.6)
	end
	local function containerRow(x: number, z: number, degrees: number, count: number, stackFirst: boolean)
		local step = if degrees % 180 == 0 then Vector3.new(0, 0, 9) else Vector3.new(9, 0, 0)
		for index = 0, count - 1 do
			local at = Vector3.new(x, 0, z) + step * index
			place("prop_container", at.X, at.Z, degrees)
			if stackFirst and index == 0 then
				place("prop_container", at.X, at.Z, degrees + 4, sizes.prop_container.size[2])
			end
		end
	end
	local function hill(x: number, z: number, radius: number, rampDegrees: number?)
		local mound =
			part("Hill", Vector3.one * radius * 2, CFrame.new(x, -radius * 0.55, z), Color3.fromHex("#C9A776"), props)
		mound.Shape = Enum.PartType.Ball
		if rampDegrees ~= nil then
			local ramp = Instance.new("WedgePart")
			ramp.Name = "Ramp"
			ramp.Anchored = true
			ramp.Color = Color3.fromHex("#B89A78")
			ramp.Material = Enum.Material.SmoothPlastic
			ramp.Size = Vector3.new(6, radius * 0.45, radius * 1.2)
			local outward = CFrame.Angles(0, math.rad(rampDegrees), 0)
			ramp.CFrame = CFrame.new(x, 0, z) * outward * CFrame.new(0, radius * 0.225, -radius * 1.15)
			ramp.Parent = props
		end
	end

	place("prop_magnet_crane", 52, 34, 0)
	place("prop_magnet_crane", span + 8, 40, 200, 0, 0.8)
	-- Grosse Schrotthaufen hinten und an den Seiten
	place("prop_scrap_pile", 4, 46, 15, 0, 1.8)
	place("prop_scrap_pile", 98, 48, -10, 0, 1.6)
	place("prop_scrap_pile", span - 12, 46, -30, 0, 2.0)
	place("prop_scrap_pile", -28, 26, 70, 0, 1.4)
	place("prop_scrap_pile", -26, -58, 40, 0, 1.3)
	place("prop_scrap_pile", 52, -6, 0, 0, 0.8)
	place("prop_scrap_pile", 112, 8, 120, 0, 0.8)
	-- Container-Reihen: rechts entlang der Seite, links hinten; jeweils einer gestapelt
	containerRow(span + 18, -62, 90, 3, true)
	containerRow(-30, 44, 0, 2, true)
	-- Gestapelte Wracks und einzelne Wracks vorne
	stackedWrecks(-24, -30, 75)
	stackedWrecks(84, -60, 10)
	stackedWrecks(span + 20, 12, 95)
	place("prop_car_wreck", 64, -34, 20)
	place("prop_car_wreck", span - 30, -36, -15)
	place("prop_car_wreck", 140, -62, 170)
	-- Reifenstapel verteilt, auch in den Luecken zwischen den Zonen
	place("prop_tire_stack", -14, -12, 0)
	place("prop_tire_stack", 104, -34, 40)
	place("prop_tire_stack", span + 18, 32, 0)
	place("prop_tire_stack", 50, 14, 60)
	place("prop_tire_stack", 114, -14, 10)
	place("prop_tire_stack", 0, -64, 30)
	-- Fass-Gruppen in verschiedenen Lackfarben
	local function barrelGroup(x: number, z: number, seed: number)
		local barrelRng = Random.new(seed)
		local colors = { "deco_barrel_red", "deco_barrel_blue", "deco_barrel_green", "deco_barrel_yellow" }
		for index = 1, 4 do
			local name = colors[(index + seed) % #colors + 1]
			place(
				name,
				x + (index % 2) * 3.2 + barrelRng:NextNumber(-0.4, 0.4),
				z + math.floor((index - 1) / 2) * 3.2,
				barrelRng:NextNumber(0, 360),
				0,
				1.6
			)
		end
	end
	barrelGroup(30, -66, 1)
	barrelGroup(-34, -42, 2)
	barrelGroup(110, 30, 3)
	barrelGroup(span + 10, -24, 4)
	barrelGroup(54, 50, 5)

	-- Sandverwehungen: flache, breite Wellen (tief versenkte Kugeln) auf freien Sandflaechen.
	local duneColors = { Color3.fromHex("#DCC08F"), Color3.fromHex("#CFB283") }
	local dunes = {
		{ -20, -64, 14 },
		{ 50, -70, 12 },
		{ 120, -66, 15 },
		{ 172, 4, 11 },
		{ -32, 14, 10 },
		{ 82, 38, 12 },
		{ 136, 44, 10 },
	}
	for index, dune in dunes do
		local radius = dune[3]
		local wave = part(
			"Dune",
			Vector3.one * radius * 2,
			CFrame.new(dune[1], -radius * 0.9, dune[2]),
			duneColors[index % 2 + 1],
			ground
		)
		wave.Shape = Enum.PartType.Ball
		wave.Material = Enum.Material.Sand
	end
	-- Kies: kleine graue Steine in lockeren Flecken.
	local gravelRng = Random.new(11)
	local gravelColors = { Color3.fromHex("#6E7781"), Color3.fromHex("#8A8F96"), Color3.fromHex("#5B5F66") }
	for _ = 1, 10 do
		local cx = gravelRng:NextNumber(minX + 12, maxX - 12)
		local cz = if gravelRng:NextNumber() < 0.6
			then gravelRng:NextNumber(minZ + 8, frontZ - 6)
			else gravelRng:NextNumber(ZONE_SIZE.Z / 2 + 6, maxZ - 8)
		for _ = 1, 14 do
			local size = gravelRng:NextNumber(0.3, 0.7)
			local stone = part(
				"Gravel",
				Vector3.new(size, size * 0.6, size * gravelRng:NextNumber(0.8, 1.3)),
				CFrame.new(cx + gravelRng:NextNumber(-3, 3), 0.15, cz + gravelRng:NextNumber(-3, 3))
					* CFrame.Angles(0, gravelRng:NextNumber(0, math.pi), 0),
				gravelColors[gravelRng:NextInteger(1, #gravelColors)],
				ground
			)
			stone.Material = Enum.Material.Slate
			stone.CanCollide = false
		end
	end

	-- Sandhuegel mit Rampen
	hill(-24, -2, 9, 90)
	hill(span + 24, -38, 8, -90)
	hill(150, -62, 7, 180)

	-- Zaun rundherum (Element 16,6 Studs, Vorderseite zeigt nach innen).
	local fenceLength = (PropShapes :: any).prop_fence.size[1]
	local function fenceLine(from: Vector3, to: Vector3, degrees: number)
		local count = math.ceil((to - from).Magnitude / fenceLength)
		for k = 0, count - 1 do
			local point = from:Lerp(to, (k + 0.5) / count)
			place("prop_fence", point.X, point.Z, degrees)
		end
	end
	fenceLine(Vector3.new(minX, 0, maxZ), Vector3.new(maxX, 0, maxZ), 180)
	fenceLine(Vector3.new(minX, 0, minZ), Vector3.new(maxX, 0, minZ), 0)
	fenceLine(Vector3.new(minX, 0, minZ), Vector3.new(minX, 0, maxZ), 90)
	fenceLine(Vector3.new(maxX, 0, minZ), Vector3.new(maxX, 0, maxZ), -90)

	local bounds = { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ }
	if useTerrain then
		Ground.build(workspace.Terrain, bounds, zoneAreas)
	end
	if next(backdrop) ~= nil then
		Backdrop.build(backdrop, bounds, root)
	end

	root.Parent = container
	-- Andere SpawnLocations (z. B. aus einer Studio-Vorlage) zur Laufzeit abschalten; gespawnt wird an der Waage.
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant ~= spawn then
			descendant.Enabled = false
		end
	end
	return root
end

return World
