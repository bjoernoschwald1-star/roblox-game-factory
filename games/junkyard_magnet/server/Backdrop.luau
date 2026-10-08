--!strict
-- Hintergrund ausserhalb des Zauns von Junkyard Magnet: hochgeladene, nach Material geteilte Blender-Modelle (bg_*,
-- art/scripts/jm_backdrop.py) rundherum, nach aussen gestaffelt:
--   nah (6-50 Studs hinter dem Zaun): detaillierte Schrottberge, Baeume, Buesche, eine Strommast-Reihe mit Leitungen
--   mittel (60-260): grobe Schrottberge (niedrige Detailstufe, 136 Dreiecke) und Duenen
--   fern (240-280): Fabrik-Silhouette am Horizont, die im Dunst (Atmosphere) auslaeuft. Nicht weiter weg: Bei
--   automatischer Grafikqualitaet (Studio, Handy) wurde sie im Spieltest ab etwa 450 Studs nicht mehr gezeichnet.
-- Reine Kulisse: verankert, ohne Kollision, ohne Abfragen und Beruehrung; ab der mittleren Staffel ohne Schatten.
-- Faerbung: Der Import liefert jeden Teil grau; jeder MeshPart heisst c_<HEX>_<Material> und bekommt diese Farbe
-- und dieses Material. Fehlt ein Modell, entfaellt es (kein Bauteil-Ersatz noetig). Fest geseedet.
local MeshModels = require(script.Parent:WaitForChild("MeshModels"))

local Backdrop = {}

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }

local SEED = 61
local WIRE_COLOR = Color3.fromHex("#2B2B2E")

-- Farbe und Material aus dem Teilnamen c_<HEX>_<Material>; nil bei fremdem Namen.
function Backdrop.parseTag(name: string): (Color3?, Enum.Material?)
	local hex, materialName = string.match(name, "^c_(%x%x%x%x%x%x)_(%a+)$")
	if hex == nil then
		return nil, nil
	end
	local found, material = pcall(function()
		return (Enum.Material :: any)[materialName]
	end)
	return Color3.fromHex(hex :: string),
		if found and typeof(material) == "EnumItem" then material else Enum.Material.SmoothPlastic
end

-- Faerbt eine Vorlage ein und macht sie zu reiner Kulisse; Drehpunkt Mitte unten im Ursprung (wie in Blender).
function Backdrop.prepare(model: Model): Model
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			local color, material = Backdrop.parseTag(part.Name)
			if color ~= nil then
				part.Color = color
				part.Material = material :: Enum.Material
			end
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
		end
	end
	model.WorldPivot = CFrame.new()
	return model
end

local function place(template: Model, position: Vector3, yaw: number, scale: number, shadow: boolean, parent: Instance)
	local model = template:Clone()
	if scale ~= 1 then
		model:ScaleTo(scale)
	end
	model:PivotTo(CFrame.new(position) * CFrame.Angles(0, yaw, 0) * MeshModels.IMPORT_TURN)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.CastShadow = shadow
		end
	end
	model.Parent = parent
	return model
end

local function wire(from: Vector3, to: Vector3, parent: Instance)
	local part = Instance.new("Part")
	part.Name = "Wire"
	part.Shape = Enum.PartType.Cylinder
	-- 0,35 Studs: duenner wirkten die Leitungen auf Entfernung wie gestrichelte Linien.
	part.Size = Vector3.new((to - from).Magnitude, 0.35, 0.35)
	-- Zylinderachse ist lokal X: nach der Leitungsrichtung ausrichten.
	part.CFrame = CFrame.lookAt((from + to) / 2, to) * CFrame.Angles(0, math.pi / 2, 0)
	part.Color = WIRE_COLOR
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = parent
end

-- Baut den Hintergrund um das Rechteck bounds (Zaun). templates[name] = vorbereitete Vorlage (prepare).
-- Liefert den Ordner und die Anzahl gesetzter Modelle.
function Backdrop.build(templates: { [string]: Model }, bounds: Bounds, parent: Instance): (Folder, number)
	local folder = Instance.new("Folder")
	folder.Name = "Backdrop"
	local rng = Random.new(SEED)
	local cx, cz = (bounds.minX + bounds.maxX) / 2, (bounds.minZ + bounds.maxZ) / 2
	local hx, hz = (bounds.maxX - bounds.minX) / 2, (bounds.maxZ - bounds.minZ) / 2
	local count = 0

	-- Punkt im Abstand distance ausserhalb des Zauns in Richtung angle; Blick zur Kartenmitte.
	local function ringPoint(angle: number, distance: number): (Vector3, number)
		local dx, dz = math.cos(angle), math.sin(angle)
		local t = math.min(hx / math.max(math.abs(dx), 1e-3), hz / math.max(math.abs(dz), 1e-3))
		local position = Vector3.new(cx + dx * (t + distance), 0, cz + dz * (t + distance))
		return position, math.atan2(cx - position.X, cz - position.Z)
	end
	local function scatter(
		name: string,
		amount: number,
		near: number,
		far: number,
		minScale: number,
		maxScale: number,
		shadow: boolean,
		evenly: boolean?
	)
		local template = templates[name]
		if template == nil then
			return
		end
		local offset = rng:NextNumber(0, 2 * math.pi)
		for index = 1, amount do
			local angle = if evenly
				then offset + (index - 1) * 2 * math.pi / amount + rng:NextNumber(-0.2, 0.2)
				else rng:NextNumber(0, 2 * math.pi)
			local position, yaw = ringPoint(angle, rng:NextNumber(near, far))
			place(
				template,
				position,
				yaw + rng:NextNumber(-0.4, 0.4),
				rng:NextNumber(minScale, maxScale),
				shadow,
				folder
			)
			count += 1
		end
	end

	-- Nah: detaillierte Schrottberge, Baeume und Buesche (mit Schatten).
	scatter("bg_scrap_mountain", 4, 34, 50, 0.9, 1.2, true, true)
	scatter("bg_tree", 14, 10, 40, 0.8, 1.3, true)
	scatter("bg_bush", 18, 5, 30, 0.8, 1.4, true)
	-- Mittel: grobe Schrottberge und Duenen (ohne Schatten).
	scatter("bg_scrap_mountain_far", 8, 110, 180, 1.2, 1.8, false, true)
	scatter("bg_dune", 14, 60, 260, 1.0, 2.2, false)
	-- Fern: Fabrik-Silhouette rundherum, frontal zur Mitte.
	scatter("bg_skyline", 7, 240, 280, 1.1, 1.4, false, true)

	-- Strommast-Reihe hinter dem Zaun (Seite +Z) mit zwei Leitungen je Feld.
	local pole = templates.bg_power_pole
	if pole ~= nil then
		local z = bounds.maxZ + 24
		local previous: { Vector3 }? = nil
		local x = bounds.minX - 150
		while x <= bounds.maxX + 150 do
			-- Traversen quer zur Leitung (Leitung entlang X).
			place(pole, Vector3.new(x, 0, z), math.pi / 2, 1, true, folder)
			count += 1
			local ends = { Vector3.new(x, 33.4, z - 5.4), Vector3.new(x, 33.4, z + 5.4) }
			if previous ~= nil then
				for k = 1, 2 do
					wire(previous[k], ends[k], folder)
				end
			end
			previous = ends
			x += 48
		end
	end

	folder.Parent = parent
	return folder, count
end

return Backdrop
