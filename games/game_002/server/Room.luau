--!strict
-- Probe-Raum Game #002: laedt die Stations-Module (InsertService:LoadAsset), haengt je Modul die
-- SurfaceAppearance-Vorlage aus ServerStorage.Game002Surfaces an (Karten setzt Rojo, Skripte duerfen sie nicht
-- schreiben) und baut daraus Raum (24 x 24 Studs) und Gang, dazu Lichter, Neon-Akzente und Partikel-Emitter.
-- Look-Runde 2: Wandfolge aus drei Varianten (config.walls), Nebenraeume hinter den Fenstern, sichtbare Lichtkegel
-- (Beam), Notlicht an der Westwand, Deko (Lueftungsgitter, Warnschilder, Pfuetzen), Kabel als RopeConstraint.
-- Nur Optik: keine Spielregeln, keine Remotes. Bewegung (Flackern, Drohne, Funken) macht der Client anhand des
-- Attributs ProbeConfig.EFFECT_ATTRIBUTE.
--
-- Koordinaten: Akzent-Positionen stehen in absoluten Blender-Koordinaten des Moduls (x Breite, y Tiefe mit
-- Vorderseite bei -y, z Hoehe) und werden mit at() ueber CENTERS (Huellen-Mitte) und fromBlender umgerechnet.
-- MESH_TURN: Drehung des importierten Meshes, damit die Vorderseite in Blickrichtung zeigt. Im Spieltest geprueft:
-- nach Zuruecksetzen des PivotOffset zeigt die Blender-Vorderseite (-y) bereits nach -Z (LookVector), also keine
-- Drehung; die Blender-Achsen liegen dann bei (-x, z, y).
-- Doku: https://create.roblox.com/docs/reference/engine/classes/InsertService#LoadAsset
--       https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance
local Room = {}

Room.MESH_TURN = CFrame.new()

export type Templates = { [string]: Model }

local function fromBlender(x: number, y: number, z: number): Vector3
	return Vector3.new(-x, z, y)
end
Room.fromBlender = fromBlender

-- Laedt alle Module parallel; liefert Vorlagen (Model mit PrimaryPart = Haupt-MeshPart) und Fehlerliste.
function Room.loadModules(
	assets: { [string]: number },
	surfaces: Instance,
	loader: ((number) -> Instance)?
): (Templates, { string })
	local load = loader
		or function(assetId: number): Instance
			return game:GetService("InsertService"):LoadAsset(assetId)
		end
	local templates: Templates = {}
	local failed: { string } = {}
	local pending = 0
	for name, assetId in assets do
		pending += 1
		task.spawn(function()
			local ok, result = pcall(load, assetId)
			if not ok or result == nil then
				table.insert(failed, name .. ": " .. tostring(result))
			else
				-- Haupt-MeshPart = gleichnamiges Mesh; das Asset enthaelt auch ein gleichnamiges Model, daher gezielt
				-- nach MeshParts suchen (sonst wird beim Artefakt der Kristall zum Hauptteil)
				local main: Instance? = nil
				for _, part in result:GetDescendants() do
					if part:IsA("MeshPart") and part.Name == name then
						main = part
						break
					end
				end
				if main == nil then
					main = result:FindFirstChildWhichIsA("MeshPart", true)
				end
				if main == nil then
					table.insert(failed, name .. ": kein MeshPart")
				else
					local model = Instance.new("Model")
					model.Name = name
					for _, part in result:GetDescendants() do
						if part:IsA("BasePart") then
							part.Anchored = true
							part.Parent = model
						end
					end
					local surface = surfaces:FindFirstChild(name)
					if surface ~= nil and surface:IsA("SurfaceAppearance") then
						surface:Clone().Parent = main
					else
						table.insert(failed, name .. ": keine SurfaceAppearance-Vorlage")
					end
					-- Der Import bringt einen gedrehten PivotOffset mit; ohne Zuruecksetzen kippt PivotTo das Modul
					(main :: MeshPart).PivotOffset = CFrame.new()
					model.PrimaryPart = main :: MeshPart
					templates[name] = model
				end
				result:Destroy()
			end
			pending -= 1
		end)
	end
	while pending > 0 do
		task.wait()
	end
	table.sort(failed)
	return templates, failed
end

local function tag(instance: Instance, effect: string, attribute: string)
	instance:SetAttribute(attribute, effect)
end

local function neon(
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	parent: Instance,
	shape: Enum.PartType?
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CastShadow = false
	if shape ~= nil then
		part.Shape = shape
	end
	part.Parent = parent
	return part
end

local function emitterPart(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	return part
end

-- Mitte der Huelle je Modul in Blender-Koordinaten (station_modules.py, Bericht "Mitte"); Akzente werden in
-- absoluten Blender-Koordinaten des Moduls angegeben und hier auf die Modulmitte bezogen.
local CENTERS: { [string]: Vector3 } = {
	station_door = Vector3.new(0, -0.083, 6),
	station_ceiling_pipes = Vector3.new(0, 0, 1.525),
	station_cart = Vector3.new(0.315, 0, 1.526),
	station_console = Vector3.new(0.199, 0.135, 2.113),
	station_drone = Vector3.new(0, 0, 0.255),
	station_wall_panel = Vector3.new(0, 0, 6),
	station_wall_window = Vector3.new(0, -0.2, 6),
	station_wall_damaged = Vector3.new(0, -0.531, 6),
	station_vent = Vector3.new(0, -0.03, 0),
	station_warning_sign = Vector3.new(0, -0.01, 0.209),
}
Room.CENTERS = CENTERS

local WALL_MODULES: { [string]: string } = {
	panel = "station_wall_panel",
	window = "station_wall_window",
	damaged = "station_wall_damaged",
}

-- Abstand der Montageflaeche (Vorderseite der Wandplatten) und Rueckseite der Standardwand zur Wandmitte
local MOUNT_DEPTH = 0.2
local WALL_BACK = 0.4

local function at(frame: CFrame, name: string, x: number, y: number, z: number): CFrame
	local c = CENTERS[name] or Vector3.zero
	return frame * CFrame.new(fromBlender(x - c.X, y - c.Y, z - c.Z))
end
Room.at = at

local function box(name: string, size: Vector3, cframe: CFrame, color: Color3, parent: Instance): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = Enum.Material.Metal
	part.Anchored = true
	part.Parent = parent
	return part
end

-- Leuchtender Bildschirm ohne Text: SurfaceGui mit Farbverlauf und Scanlinien aus Frames, LightInfluence 0 und
-- Brightness > 1, damit Bloom ihn leuchten laesst. Liefert die SurfaceGui (der Client dimmt deren Brightness).
function Room.screenGui(panel: BasePart, screen: any): SurfaceGui
	local gui = Instance.new("SurfaceGui")
	gui.Name = "ScreenGlow"
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = screen.guiBrightness
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = screen.pixelsPerStud
	local field = Instance.new("Frame")
	field.Name = "Field"
	field.Size = UDim2.fromScale(1, 1)
	field.BorderSizePixel = 0
	field.BackgroundColor3 = Color3.new(1, 1, 1)
	local gradient = Instance.new("UIGradient")
	gradient.Rotation = 90
	gradient.Color = ColorSequence.new(screen.glowTop, screen.glowBottom)
	gradient.Parent = field
	field.Parent = gui
	for i = 0, screen.scanlines - 1 do
		local line = Instance.new("Frame")
		line.Name = "Scanline"
		line.BorderSizePixel = 0
		line.BackgroundColor3 = Color3.new(0, 0, 0)
		line.BackgroundTransparency = screen.scanlineTransparency
		line.Size = UDim2.new(1, 0, 0, 2)
		line.Position = UDim2.fromScale(0, i / screen.scanlines)
		line.Parent = field
	end
	gui.Parent = panel
	return gui
end

function Room.build(templates: Templates, config: any, parent: Instance): Model
	local root = Instance.new("Model")
	root.Name = config.FOLDER_NAME
	local attribute: string = config.EFFECT_ATTRIBUTE
	local room = config.room
	local half = room.size / 2
	local floorTop: number = room.floorTop
	local wallTop = floorTop + room.wallHeight
	local lights = config.lights
	local effects = config.effects
	local accents = config.accents
	local decor = config.decor

	-- Modul setzen; face = Richtung, in die die Vorderseite zeigt. Liefert Modell und dessen Bezugs-CFrame.
	local function place(name: string, position: Vector3, face: Vector3): (Model?, CFrame)
		local frame = CFrame.lookAt(position, position + face) * Room.MESH_TURN
		local template = templates[name]
		if template == nil then
			return nil, frame
		end
		local model = template:Clone()
		model:PivotTo(frame)
		model.Parent = root
		return model, frame
	end
	local function sizeOf(name: string): Vector3
		local template = templates[name]
		if template == nil or template.PrimaryPart == nil then
			return Vector3.new(1, 1, 1)
		end
		return (template.PrimaryPart :: BasePart).Size
	end
	local function onFloor(name: string, x: number, z: number, face: Vector3): (Model?, CFrame)
		return place(name, Vector3.new(x, floorTop + sizeOf(name).Y / 2, z), face)
	end
	local function light(
		kind: string,
		parentPart: Instance,
		color: Color3,
		brightness: number,
		range: number,
		shadows: boolean
	): Light
		local item = Instance.new(kind) :: any
		item.Color = color
		item.Brightness = brightness
		item.Range = range
		item.Shadows = shadows
		item.Parent = parentPart
		return item
	end

	-- Boden: 3 x 3 im Raum, 2 im Gang (Gang zeigt nach -Z)
	local m: number = room.module
	local corridorEnd = -half - room.corridorModules * m
	local plateY = floorTop - sizeOf("station_floor_plate").Y / 2
	for _, x in { -m, 0, m } do
		for _, z in { -m, 0, m } do
			place("station_floor_plate", Vector3.new(x, plateY, z), Vector3.zAxis)
		end
	end
	for i = 1, room.corridorModules do
		place("station_floor_plate", Vector3.new(0, plateY, -half - (i - 0.5) * m), Vector3.zAxis)
	end

	-- Waende aus der Wandfolge (config.walls); Bezugspunkt = Mitte einer Standardwand, Varianten um ihre
	-- Huellen-Mitte versetzt, damit alle Rueckseiten in einer Ebene liegen
	local wallY = floorTop + room.wallHeight / 2
	local t = WALL_BACK
	type Slot = { ref: Vector3, face: Vector3, along: Vector3 }
	local function slot(key: string, index: number): Slot
		local across = ({ -m, 0, m })[index]
		if key == "north" then
			return { ref = Vector3.new(across, wallY, -half - t), face = Vector3.zAxis, along = Vector3.xAxis }
		elseif key == "south" then
			return { ref = Vector3.new(across, wallY, half + t), face = -Vector3.zAxis, along = Vector3.xAxis }
		elseif key == "east" then
			return { ref = Vector3.new(half + t, wallY, across), face = -Vector3.xAxis, along = Vector3.zAxis }
		elseif key == "west" then
			return { ref = Vector3.new(-half - t, wallY, across), face = Vector3.xAxis, along = Vector3.zAxis }
		elseif key == "corridorWest" or key == "corridorEast" then
			local z = -half - (index - 0.5) * m
			local sign = if key == "corridorEast" then 1 else -1
			return {
				ref = Vector3.new(sign * (m / 2 + t), wallY, z),
				face = Vector3.new(-sign, 0, 0),
				along = Vector3.zAxis,
			}
		end
		return { ref = Vector3.new(0, wallY, corridorEnd - t), face = Vector3.zAxis, along = Vector3.xAxis }
	end
	local windows: { Slot } = {}
	for key, variants in config.walls do
		for index, variant in variants do
			local name = WALL_MODULES[variant]
			if name ~= nil then
				local s = slot(key, index)
				local _, frame = place(name, s.ref - s.face * CENTERS[name].Y, s.face)
				if variant == "window" then
					table.insert(windows, s)
					-- Glas im Fensterausschnitt (Oeffnung x -2.3..2.3, z 3.7..6.9 in Blender)
					local glass = box(
						"WindowGlass",
						Vector3.new(4.6, 3.2, 0.08),
						at(frame, name, 0, 0.25, 5.3),
						accents.glass,
						root
					)
					glass.Material = Enum.Material.Glass
					glass.Transparency = accents.glassTransparency
					glass.CastShadow = false
				end
			end
		end
	end
	-- Nebenraeume hinter den Fenstern: dunkler Kasten mit schwachem Licht und einer Kisten-Silhouette
	local side = lights.sideRoom
	for _, s in windows do
		local depth: number = side.depth
		local center = s.ref - s.face * (t + depth / 2)
		local frame = CFrame.lookAt(center, center + s.face)
		local dark = Color3.fromRGB(10, 11, 13)
		local h = room.wallHeight
		box("SideBack", Vector3.new(m, h, 0.4), frame * CFrame.new(0, 0, depth / 2), dark, root)
		box("SideFloor", Vector3.new(m, 0.4, depth), frame * CFrame.new(0, -h / 2, 0), dark, root)
		box("SideCeiling", Vector3.new(m, 0.4, depth), frame * CFrame.new(0, h / 2, 0), dark, root)
		box("SideLeft", Vector3.new(0.4, h, depth), frame * CFrame.new(-m / 2, 0, 0), dark, root)
		box("SideRight", Vector3.new(0.4, h, depth), frame * CFrame.new(m / 2, 0, 0), dark, root)
		local holder = box("SideLight", Vector3.new(0.2, 0.2, 0.2), frame, dark, root)
		holder.Transparency = 1
		holder.CanCollide = false
		light("PointLight", holder, side.color, side.brightness, side.range, false)
		local crateModel = place("station_crate", (frame * CFrame.new(-1.8, -h / 2 + 1.7, 1.2)).Position, s.face)
		if crateModel ~= nil then
			crateModel.Name = "SideCrate"
		end
	end

	-- Tuer in der Nordwand: Bernstein-Akzente am Rahmen und Warnleuchte (Lesbarkeit), ohne Lichtquelle
	local door = sizeOf("station_door")
	local _, doorFrame = place("station_door", Vector3.new(0, floorTop + door.Y / 2, -half - door.Z / 2), Vector3.zAxis)
	for _, x in { -2.42, 2.42 } do
		neon(
			"DoorAccent",
			Vector3.new(0.1, 8.3, 0.06),
			at(doorFrame, "station_door", x, -0.8, 4.25),
			accents.doorFrame,
			root
		)
	end
	neon("DoorAccent", Vector3.new(5, 0.08, 0.06), at(doorFrame, "station_door", 0, -0.8, 8.5), accents.doorFrame, root)
	neon(
		"DoorBeacon",
		Vector3.new(0.5, 0.5, 0.5),
		at(doorFrame, "station_door", 0, -0.98, 9.9),
		accents.doorBeacon,
		root,
		Enum.PartType.Ball
	)
	-- Bodenmarken im Gang
	local guideZ = -half - 1.5
	while guideZ > corridorEnd + 0.5 do
		for _, x in { -m / 2 + 0.7, m / 2 - 0.7 } do
			neon("GuideLight", Vector3.new(0.25, 0.06, 0.5), CFrame.new(x, 0.63, guideZ), accents.guide, root)
		end
		guideZ -= accents.guideSpacing
	end

	-- Rotes Notlicht an der Westwand (Mitte), pulsiert
	local west = slot("west", 2)
	local mount = west.ref + west.face * MOUNT_DEPTH + Vector3.new(0, floorTop + lights.emergency.height - wallY, 0)
	local lampFrame = CFrame.lookAt(mount, mount + west.face)
	box(
		"EmergencyHousing",
		Vector3.new(1.4, 0.9, 0.3),
		lampFrame * CFrame.new(0, 0, -0.15),
		Color3.fromRGB(20, 20, 22),
		root
	)
	local redLamp = neon(
		"EmergencyLamp",
		Vector3.new(1.1, 0.6, 0.1),
		lampFrame * CFrame.new(0, 0, -0.33),
		lights.emergency.color,
		root
	)
	light("PointLight", redLamp, lights.emergency.color, lights.emergency.brightness, lights.emergency.range, true)
	tag(redLamp, "pulse", attribute)

	-- Decke: Leuchtengehaeuse in jedem Element; zwei leuchten mit engem Kegel und flackern
	local ceiling = sizeOf("station_ceiling_pipes")
	local ceilingY = wallTop + 0.5 - ceiling.Y / 2
	local litCeilings = { Vector3.new(0, ceilingY, 0), Vector3.new(0, ceilingY, -half - m / 2) }
	local ceilingSpots: { Vector3 } = {}
	for _, x in { -m, 0, m } do
		for _, z in { -m, 0, m } do
			table.insert(ceilingSpots, Vector3.new(x, ceilingY, z))
		end
	end
	for i = 1, room.corridorModules do
		table.insert(ceilingSpots, Vector3.new(0, ceilingY, -half - (i - 0.5) * m))
	end
	local lamp = lights.ceiling
	for _, spot in ceilingSpots do
		local _, frame = place("station_ceiling_pipes", spot, -Vector3.zAxis)
		local lit = false
		for _, litSpot in litCeilings do
			lit = lit or (litSpot - spot).Magnitude < 0.1
		end
		if lit then
			local strip = neon(
				"CeilingLamp",
				Vector3.new(3, 0.08, 0.85),
				at(frame, "station_ceiling_pipes", 0, 0, 1.625),
				lamp.color,
				root
			)
			local spotLight = light("SpotLight", strip, lamp.color, lamp.brightness, lamp.range, true) :: SpotLight
			spotLight.Face = Enum.NormalId.Bottom
			spotLight.Angle = lamp.angle
			-- sichtbarer Lichtkegel: Beam von der Leuchte zum Boden, zur Kamera gedreht
			local top = Instance.new("Attachment")
			top.Position = Vector3.new(0, -0.1, 0)
			top.Parent = strip
			local bottom = Instance.new("Attachment")
			bottom.Position = Vector3.new(0, -(strip.Position.Y - floorTop), 0)
			bottom.Parent = strip
			local cone = Instance.new("Beam")
			cone.Attachment0 = top
			cone.Attachment1 = bottom
			cone.Width0 = lamp.coneTop
			cone.Width1 = lamp.coneBottom
			cone.FaceCamera = true
			cone.LightEmission = 1
			cone.LightInfluence = 0
			cone.Segments = 1
			cone.Color = ColorSequence.new(lamp.color)
			cone.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, lamp.coneTransparency),
				NumberSequenceKeypoint.new(1, 1),
			})
			cone.Parent = strip
			tag(strip, "flicker", attribute)
			-- Staub im Lichtkegel
			local dustBox = emitterPart("Dust", Vector3.new(6, 7, 6), CFrame.new(spot.X, floorTop + 4.5, spot.Z), root)
			local dust = Instance.new("ParticleEmitter")
			dust.Texture = effects.dustTexture
			dust.Shape = Enum.ParticleEmitterShape.Box
			dust.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			dust.Rate = effects.dustRate
			dust.Lifetime = NumberRange.new(6, 10)
			dust.Speed = NumberRange.new(0.05, 0.25)
			dust.SpreadAngle = Vector2.new(180, 180)
			dust.Size = NumberSequence.new(0.05, 0.08)
			dust.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 1),
				NumberSequenceKeypoint.new(0.2, 0.3),
				NumberSequenceKeypoint.new(0.8, 0.3),
				NumberSequenceKeypoint.new(1, 1),
			})
			dust.Color = ColorSequence.new(Color3.fromRGB(220, 230, 240))
			dust.LightInfluence = 1
			dust.LightEmission = 0.3
			dust.Acceleration = Vector3.new(0, -0.02, 0)
			dust.RotSpeed = NumberRange.new(-20, 20)
			dust.Parent = dustBox
		end
	end
	-- Dampf aus dem Ventil am grossen Rohr (Element in der Suedost-Ecke, oben bereits gesetzt)
	local steamSpot = Vector3.new(m, ceilingY, m)
	local steamFrame = CFrame.lookAt(steamSpot, steamSpot - Vector3.zAxis) * Room.MESH_TURN
	local steamPart =
		emitterPart("Steam", Vector3.new(0.3, 0.3, 0.3), at(steamFrame, "station_ceiling_pipes", 2.4, 1.2, 0.575), root)
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = effects.steamTexture
	steam.Rate = effects.steamRate
	steam.Lifetime = NumberRange.new(1.5, 2.6)
	steam.Speed = NumberRange.new(2.5, 4)
	steam.EmissionDirection = Enum.NormalId.Bottom
	steam.SpreadAngle = Vector2.new(14, 14)
	steam.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 3.2),
	})
	steam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	steam.Color = ColorSequence.new(Color3.fromRGB(215, 225, 235))
	steam.LightInfluence = 1
	steam.Drag = 1.5
	steam.Acceleration = Vector3.new(0, -0.6, 0)
	steam.RotSpeed = NumberRange.new(-30, 30)
	steam.Parent = steamPart

	-- Konsole an der Ostwand: zwei Bildschirme als schwache tuerkise Lichtquelle (flackern leicht), Funken
	local console = sizeOf("station_console")
	local _, consoleFrame = onFloor("station_console", half - console.Z / 2 - 0.3, m / 2, -Vector3.xAxis)
	local screen = lights.screen
	for _, x in { -1.3, 1.3 } do
		local panel = box(
			"Screen",
			Vector3.new(1.9, 1.2, 0.05),
			at(consoleFrame, "station_console", x, 0.7, 3.65) * CFrame.Angles(math.rad(-8), 0, 0),
			Color3.fromRGB(4, 8, 10),
			root
		)
		panel.Material = Enum.Material.SmoothPlastic
		panel.CanCollide = false
		panel.CastShadow = false
		Room.screenGui(panel, screen)
		local glow = light("SurfaceLight", panel, screen.color, screen.brightness, screen.range, false) :: SurfaceLight
		glow.Face = Enum.NormalId.Front
		glow.Angle = screen.angle
		tag(panel, "screen", attribute)
	end
	local sparkPart =
		emitterPart("Sparks", Vector3.new(0.4, 0.2, 0.4), at(consoleFrame, "station_console", -1.6, -1.0, 2.7), root)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = effects.sparkTexture
	sparks.Rate = 0
	sparks.Lifetime = NumberRange.new(0.3, 0.8)
	sparks.Speed = NumberRange.new(6, 12)
	sparks.SpreadAngle = Vector2.new(70, 70)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.Acceleration = Vector3.new(0, -40, 0)
	sparks.Size = NumberSequence.new(0.15, 0.02)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 90, 20))
	sparks.LightEmission = 1
	sparks.Brightness = 3
	sparks.Parent = sparkPart
	local sparkLight = light("PointLight", sparkPart, Color3.fromRGB(255, 160, 60), 0, 8, false)
	sparkLight.Name = "SparkFlash"
	tag(sparkPart, "sparks", attribute)

	-- Rollwagen mit Artefakt (Kristall Neon tuerkis, Licht)
	local _, cartFrame = onFloor("station_cart", -3.5, 3, Vector3.new(1, 0, -1).Unit)
	local cradleTop = at(cartFrame, "station_cart", -0.6, 0, 2.77).Position
	local artifactSize = sizeOf("station_artifact")
	local artifact = place("station_artifact", cradleTop + Vector3.new(0, artifactSize.Y / 2, 0), -Vector3.zAxis)
	if artifact ~= nil then
		for _, part in artifact:GetDescendants() do
			if part:IsA("MeshPart") and part ~= artifact.PrimaryPart then
				part.Material = Enum.Material.Neon
				part.Color = lights.artifact.color
				part.CastShadow = false
				light(
					"PointLight",
					part,
					lights.artifact.color,
					lights.artifact.brightness,
					lights.artifact.range,
					true
				)
			end
		end
	end

	-- Kisten in der Suedwest-Ecke, Kabelbuendel an den Waenden
	local crate = sizeOf("station_crate")
	onFloor("station_crate", -half + crate.X / 2 + 0.6, half - crate.Z / 2 - 0.6, -Vector3.zAxis)
	onFloor("station_crate", -half + crate.X * 1.5 + 0.8, half - crate.Z / 2 - 0.7, Vector3.new(-0.2, 0, -1).Unit)
	place(
		"station_crate",
		Vector3.new(-half + crate.X / 2 + 0.7, floorTop + crate.Y * 1.5, half - crate.Z / 2 - 0.5),
		Vector3.new(0.3, 0, -1).Unit
	)
	local cable = sizeOf("station_cable_bundle")
	onFloor("station_cable_bundle", half - cable.Z / 2 - 0.05, -m + 1, -Vector3.xAxis)
	onFloor("station_cable_bundle", -half + cable.Z / 2 + 0.05, m / 2 - 1, Vector3.xAxis)
	onFloor("station_cable_bundle", m / 2 - cable.Z / 2, -half - m - 2, -Vector3.xAxis)

	-- Deko: Lueftungsgitter und Warnschilder auf Wandplatten, Pfuetzen auf dem Gitterboden
	local function onWall(name: string, entry: any)
		local s = slot(entry.wall, entry.slot)
		local depth = sizeOf(name).Z
		local position = s.ref
			+ s.face * (MOUNT_DEPTH + depth / 2)
			+ s.along * entry.along
			+ Vector3.new(0, floorTop + entry.height - wallY, 0)
		place(name, position, s.face)
	end
	for _, entry in decor.vents do
		onWall("station_vent", entry)
	end
	for _, entry in decor.signs do
		onWall("station_warning_sign", entry)
	end
	local puddle = sizeOf("station_puddle")
	for _, entry in decor.puddles do
		local yaw = math.rad(entry.yaw)
		-- auf dem Gitterrost (Oberkante 0.07 unter der Bolzen-Oberkante floorTop)
		place(
			"station_puddle",
			Vector3.new(entry.x, floorTop - 0.07 + puddle.Y / 2, entry.z),
			Vector3.new(math.sin(yaw), 0, math.cos(yaw))
		)
	end
	-- herabhaengende Kabel: sichtbare RopeConstraint zwischen Deckenpunkten bzw. mit frei pendelndem Stecker
	for index, entry in decor.cables do
		local anchor = emitterPart("CableAnchor", Vector3.new(0.3, 0.3, 0.3), CFrame.new(entry.from), root)
		local a0 = Instance.new("Attachment")
		a0.Parent = anchor
		local endPart: BasePart
		if entry.to ~= nil then
			endPart = emitterPart("CableAnchor", Vector3.new(0.3, 0.3, 0.3), CFrame.new(entry.to), root)
		else
			local plug = Instance.new("Part")
			plug.Name = "CablePlug"
			plug.Shape = Enum.PartType.Cylinder
			plug.Size = Vector3.new(0.6, 0.3, 0.3)
			plug.CFrame = CFrame.new(entry.from - Vector3.new(0, entry.length, 0)) * CFrame.Angles(0, 0, math.rad(90))
			plug.Color = decor.cableColor
			plug.Material = Enum.Material.Metal
			plug.CanCollide = false
			plug.Parent = root
			endPart = plug
		end
		local a1 = Instance.new("Attachment")
		a1.Parent = endPart
		local rope = Instance.new("RopeConstraint")
		rope.Name = "HangingCable" .. index
		rope.Attachment0 = a0
		rope.Attachment1 = a1
		rope.Length = entry.length
		rope.Visible = true
		rope.Thickness = entry.thickness
		rope.Color = BrickColor.new(decor.cableColor)
		rope.Parent = anchor
	end

	-- Drohne (dunkles Metall) mit rotem Auge und Suchscheinwerfer; schwebt (Client) um diesen Punkt
	local drone, droneFrame =
		place("station_drone", Vector3.new(5, floorTop + lights.drone.hoverHeight, -3), Vector3.new(0, 0, 1))
	if drone ~= nil then
		local lens = neon(
			"DroneEye",
			Vector3.new(0.45, 0.45, 0.45),
			at(droneFrame, "station_drone", 0, -1.02, -0.12),
			lights.drone.color,
			drone,
			Enum.PartType.Ball
		)
		-- Blickrichtung des Auges nach vorn-unten (Face Front des Teils)
		lens.CFrame = CFrame.lookAt(lens.Position, lens.Position + Vector3.new(0, -1.2, 1).Unit)
		local beam =
			light("SpotLight", lens, lights.drone.color, lights.drone.brightness, lights.drone.range, true) :: SpotLight
		beam.Angle = lights.drone.angle
		beam.Face = Enum.NormalId.Front
		tag(drone, "drone", attribute)
	end

	-- sehr schwache Fuelllichter ohne Schatten
	for _, point in lights.fill.points do
		local holder = emitterPart("FillLight", Vector3.new(0.2, 0.2, 0.2), CFrame.new(point.position), root)
		light("PointLight", holder, lights.fill.color, point.brightness, point.range, false)
	end

	-- Startpunkt im Raum, Blick zur Tuer
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "ProbeSpawn"
	spawn.Size = Vector3.new(4, 0.2, 4)
	spawn.CFrame = CFrame.new(0, floorTop + 0.1, 8)
	spawn.Transparency = 1
	spawn.CanCollide = false
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Parent = root

	root.Parent = parent
	return root
end

return Room
