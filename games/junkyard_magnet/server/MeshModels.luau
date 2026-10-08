--!strict
-- Laedt die hochgeladenen Blender-Modelle (ModelAssets) und macht daraus Vorlagen fuer Kulisse und Items.
-- Lade-Weg: InsertService:LoadAsset im Server. MeshPart.MeshId ist fuer Skripte nicht schreibbar, daher kein
-- Aufbau eigener MeshParts; LoadAsset liefert ein Model mit dem fertigen MeshPart (Assets des Place-Besitzers).
-- Doku: https://create.roblox.com/docs/reference/engine/classes/InsertService#LoadAsset
--       https://create.roblox.com/docs/reference/engine/classes/MeshPart#MeshId
--
-- Der Import ergibt je Modell genau einen MeshPart in Grau (Plastic, ohne Textur): Die Blender-Materialien kommen
-- nicht an. Nachkorrektur im Spiel: Farbe und Material des MeshParts = vorherrschende Farbe/Material der
-- Blender-Grundformen (Volumen-gewichtet, PropShapes/ItemShapes); alle Grundformen in anderen Farben/Materialien
-- (Akzente, z. B. Neon-Streifen) bleiben als sichtbare Parts, um ACCENT_GROW vergroessert gegen Z-Fighting.
-- Ausrichtung: Der Import dreht um 180 Grad um Y (IMPORT_TURN, im Spieltest gegen die Bauteil-Version geprueft);
-- die Groesse stimmt (1 Stud = 1 Blender-Einheit). Fehlt ein Modell oder laedt es nicht, bleibt die Bauteil-Version.
local MeshModels = {}

MeshModels.IMPORT_TURN = CFrame.Angles(0, math.pi, 0)
MeshModels.FOLDER_NAME = "JunkyardModels"
MeshModels.ACCENT_GROW = 0.04 -- Studs je Achse

local MATERIALS: { [string]: Enum.Material } = {
	SmoothPlastic = Enum.Material.SmoothPlastic,
	Metal = Enum.Material.Metal,
	Neon = Enum.Material.Neon,
	Foil = Enum.Material.Foil,
}

local function rowCFrame(row: { any }): CFrame
	return CFrame.new(
		row[5],
		row[6],
		row[7],
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
end

-- Begrenzungsquader der Grundformen (Zylinder und Kugeln als Quader): Mitte und Groesse.
function MeshModels.bounds(rows: { { any } }): (Vector3, Vector3)
	local low = Vector3.new(math.huge, math.huge, math.huge)
	local high = -low
	for _, row in rows do
		local cframe = rowCFrame(row)
		for _, sx in { -0.5, 0.5 } do
			for _, sy in { -0.5, 0.5 } do
				for _, sz in { -0.5, 0.5 } do
					local corner = cframe * Vector3.new(row[2] * sx, row[3] * sy, row[4] * sz)
					low = low:Min(corner)
					high = high:Max(corner)
				end
			end
		end
	end
	return (low + high) / 2, high - low
end

local function rowKey(row: { any }): string
	return tostring(row[17]) .. "|" .. tostring(row[18])
end

-- Vorherrschende Farbe und Material (groesstes Volumen je Kombination).
function MeshModels.dominant(rows: { { any } }): (Color3, Enum.Material)
	local volumes: { [string]: number } = {}
	local bestKey, bestVolume = nil :: string?, -1
	for _, row in rows do
		local key = rowKey(row)
		volumes[key] = (volumes[key] or 0) + row[2] * row[3] * row[4]
		if volumes[key] > bestVolume then
			bestKey, bestVolume = key, volumes[key]
		end
	end
	assert(bestKey ~= nil, "MeshModels.dominant: no rows")
	local hex, material = string.match(bestKey :: string, "^(.-)|(.*)$")
	return Color3.fromHex(hex :: string), MATERIALS[material :: string] or Enum.Material.SmoothPlastic
end

-- Akzente: Indizes der Zeilen, deren Farbe/Material nicht die vorherrschende ist.
function MeshModels.accents(rows: { { any } }): { [number]: boolean }
	local color, material = MeshModels.dominant(rows)
	local result: { [number]: boolean } = {}
	for index, row in rows do
		if Color3.fromHex(row[17]) ~= color or (MATERIALS[row[18]] or Enum.Material.SmoothPlastic) ~= material then
			result[index] = true
		end
	end
	return result
end

-- Sichtbarer Akzent-Part einer Zeile (ohne Kollision), relativ zum Drehpunkt pivot.
function MeshModels.accentPart(row: { any }, pivot: CFrame, rowScale: number): Part
	local SHAPES: { [string]: Enum.PartType } =
		{ Block = Enum.PartType.Block, Cylinder = Enum.PartType.Cylinder, Ball = Enum.PartType.Ball }
	local grow = MeshModels.ACCENT_GROW
	local part = Instance.new("Part")
	part.Name = "Accent"
	part.Shape = SHAPES[row[1]] or Enum.PartType.Block
	part.Size = Vector3.new(row[2] * rowScale + grow, row[3] * rowScale + grow, row[4] * rowScale + grow)
	local cframe = rowCFrame(row)
	part.CFrame = pivot * CFrame.new(cframe.Position * rowScale) * cframe.Rotation
	part.Color = Color3.fromHex(row[17])
	part.Material = MATERIALS[row[18]] or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	return part
end

-- Sichtbarer MeshPart fuer ein Objekt: Vorlage geklont, skaliert, eingefaerbt; Lage relativ zum Drehpunkt
-- (Mitte unten) = pivot. rows/rowScale beschreiben die Grundformen (Mitte, Farbe), meshScale die Mesh-Skalierung.
function MeshModels.visual(template: MeshPart, rows: { { any } }, pivot: CFrame, rowScale: number, meshScale: number)
	local center = MeshModels.bounds(rows)
	local color, material = MeshModels.dominant(rows)
	local mesh = template:Clone()
	mesh.Name = "Mesh"
	mesh.Size = template.Size * meshScale
	mesh.CFrame = pivot * CFrame.new(center * rowScale) * MeshModels.IMPORT_TURN
	mesh.Color = color
	mesh.Material = material
	mesh.Transparency = 0
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	return mesh
end

-- Laedt alle Modelle parallel; loader(assetId) -> Instance (Standard InsertService:LoadAsset). Liefert die
-- MeshPart-Vorlagen je Name und die Namen, die nicht geladen werden konnten (mit Grund).
function MeshModels.loadAll(
	ids: { [string]: number },
	loader: ((number) -> Instance)?,
	timeoutSeconds: number?
): ({ [string]: MeshPart }, { string })
	local load = loader
		or function(assetId: number): Instance
			return game:GetService("InsertService"):LoadAsset(assetId)
		end
	local templates: { [string]: MeshPart } = {}
	local failed: { string } = {}
	local pending = 0
	for name, assetId in ids do
		pending += 1
		task.spawn(function()
			local ok, result = pcall(load, assetId)
			local mesh = if ok and typeof(result) == "Instance"
				then result:FindFirstChildWhichIsA("MeshPart", true)
				else nil
			if mesh ~= nil then
				mesh.Parent = nil
				templates[name] = mesh
			else
				table.insert(failed, name .. ": " .. (if ok then "kein MeshPart" else tostring(result)))
			end
			if ok and typeof(result) == "Instance" then
				result:Destroy()
			end
			pending -= 1
		end)
	end
	local deadline = os.clock() + (timeoutSeconds or 20)
	while pending > 0 and os.clock() < deadline do
		task.wait(0.05)
	end
	if pending > 0 then
		table.insert(failed, pending .. " Modelle nach Zeitlimit nicht geladen")
	end
	table.sort(failed)
	return templates, failed
end

-- Item-Vorlagen fuer den Client: je Asset ein Model mit dem eingefaerbten MeshPart, Drehpunkt Mitte unten im
-- Ursprung (WorldPivot). itemShapes[asset] = { parts }, Zeilen bereits um itemScale vergroessert.
function MeshModels.itemTemplates(
	templates: { [string]: MeshPart },
	itemShapes: { [string]: any },
	itemScale: number,
	parent: Instance
): number
	local count = 0
	for asset, shape in itemShapes do
		local template = templates[asset]
		if template ~= nil and string.sub(asset, 1, 5) == "item_" then
			local model = Instance.new("Model")
			model.Name = asset
			MeshModels.visual(template, shape.parts, CFrame.new(), 1, itemScale).Parent = model
			for index in MeshModels.accents(shape.parts) do
				MeshModels.accentPart(shape.parts[index], CFrame.new(), 1).Parent = model
			end
			model.WorldPivot = CFrame.new()
			model.Parent = parent
			count += 1
		end
	end
	return count
end

return MeshModels
