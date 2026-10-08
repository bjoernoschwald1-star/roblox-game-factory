--!strict
-- Boden von Junkyard Magnet aus Roblox-Terrain statt einer Platte: eine grosse, ebene Sandflaeche, die weit ueber
-- den Zaun hinaus reicht, ausserhalb flache Sandkuppen und Flecken aus Erde und Gras, und je Zone eine Flaeche in
-- eigener Bodenart mit unregelmaessigem, gewelltem Rand (Terrain blendet die Materialien an den Voxelkanten weich
-- ineinander). Zonen bleiben ueber Farbe und Bodenart erkennbar.
-- Hoehe: Terrain arbeitet in 4-Stud-Voxeln, und sich ueberlappende Fuellungen wuchsen im Test zu Beulen. Deshalb
-- gibt es eine einzige ebene Fuellung (TOP empirisch: Oberflaeche bei etwa y 0, Hoehe der Requisiten und der
-- unsichtbaren Zonen-Oberseiten); Zonen und Flecken aendern danach nur das Material (ReadVoxels/WriteVoxels).
-- Nur die Sandkuppen ausserhalb ragen heraus.
-- Die Bodenfarben setzt Terrain:SetMaterialColor auf die Palette (STYLE.md); das gilt fuer das ganze Terrain.
-- Fest geseedet. Doku: https://create.roblox.com/docs/reference/engine/classes/Terrain#FillBlock
--       https://create.roblox.com/docs/reference/engine/classes/Terrain#SetMaterialColor
local Ground = {}

export type Bounds = { minX: number, maxX: number, minZ: number, maxZ: number }
export type ZoneArea = { center: Vector3, size: Vector3 }

Ground.EXTENT = 1600 -- Kantenlaenge der Sandflaeche (bis hinter die Fabrik-Silhouette; weiter zeichnet Roblox nicht)
Ground.DEPTH = 8
Ground.TOP = -2 -- Oberkante der Fuellung; ergibt im Spieltest eine Oberflaeche bei etwa y 0
Ground.ZONE_MATERIALS = { Enum.Material.Ground, Enum.Material.Asphalt, Enum.Material.Pavement, Enum.Material.Slate }

local SEED = 71
local PAINT_REACH = 220 -- so weit ausserhalb des Zauns werden Flecken gemalt
local COLORS: { [Enum.Material]: Color3 } = {
	[Enum.Material.Sand] = Color3.fromHex("#D9B98A"),
	[Enum.Material.Ground] = Color3.fromHex("#B07A4E"),
	[Enum.Material.Asphalt] = Color3.fromHex("#5A5652"),
	[Enum.Material.Pavement] = Color3.fromHex("#C9BBA2"),
	[Enum.Material.Slate] = Color3.fromHex("#5C7186"), -- Hafen: nasser, blaugrauer Kai
	[Enum.Material.Grass] = Color3.fromHex("#7A9E3E"),
}

-- Bodenart je Zone (Reihenfolge der Zonen; wiederholt sich bei mehr Zonen).
function Ground.zoneMaterial(index: number): Enum.Material
	return Ground.ZONE_MATERIALS[(index - 1) % #Ground.ZONE_MATERIALS + 1]
end

-- Liegt (dx, dz) relativ zur Zonenmitte innerhalb des unregelmaessigen Zonenrands? Abgerundetes Rechteck
-- (Exponent 4) mit gewelltem Radius; phase verschiebt die Wellen je Zone.
function Ground.insideZone(dx: number, dz: number, hx: number, hz: number, phase: number): boolean
	local r = ((math.abs(dx) / hx) ^ 4 + (math.abs(dz) / hz) ^ 4) ^ 0.25
	local angle = math.atan2(dz, dx)
	local edge = 1 + 0.07 * math.sin(3 * angle + phase) + 0.05 * math.sin(7 * angle + 2 * phase)
	return r < edge
end

-- Fuellt den Boden. zones = Flaechen der Zonen-Parts (nur Mitte und Groesse in X/Z werden genutzt).
function Ground.build(terrain: Terrain, bounds: Bounds, zones: { ZoneArea })
	for material, color in COLORS do
		terrain:SetMaterialColor(material, color)
	end
	local rng = Random.new(SEED)
	local cx, cz = (bounds.minX + bounds.maxX) / 2, (bounds.minZ + bounds.maxZ) / 2
	local depth = Ground.DEPTH
	terrain:FillBlock(
		CFrame.new(cx, Ground.TOP - depth / 2, cz),
		Vector3.new(Ground.EXTENT, depth, Ground.EXTENT),
		Enum.Material.Sand
	)
	local function outside(x: number, z: number, margin: number): boolean
		return x < bounds.minX - margin
			or x > bounds.maxX + margin
			or z < bounds.minZ - margin
			or z > bounds.maxZ + margin
	end
	local function randomOutside(margin: number, reach: number): (number, number)
		for _ = 1, 20 do
			local x = rng:NextNumber(bounds.minX - reach, bounds.maxX + reach)
			local z = rng:NextNumber(bounds.minZ - reach, bounds.maxZ + reach)
			if outside(x, z, margin) then
				return x, z
			end
		end
		return bounds.maxX + margin + reach / 2, cz
	end
	-- Flache Sandkuppen ausserhalb: Kugelkappen, die einige Studs aus dem Boden ragen.
	for _ = 1, 12 do
		local radius = rng:NextNumber(20, 40)
		local x, z = randomOutside(radius + 6, 260)
		terrain:FillBall(Vector3.new(x, Ground.TOP - radius + rng:NextNumber(4, 9), z), radius, Enum.Material.Sand)
	end
	-- Flecken aus Erde und Gras ausserhalb (Kreise).
	local patches: { { x: number, z: number, radius: number, material: Enum.Material } } = {}
	for index = 1, 26 do
		local radius = rng:NextNumber(8, 22)
		local x, z = randomOutside(radius + 4, PAINT_REACH - 30)
		table.insert(patches, {
			x = x,
			z = z,
			radius = radius,
			material = if index % 3 == 0 then Enum.Material.Grass else Enum.Material.Ground,
		})
	end
	local phases: { number } = {}
	for index in zones do
		phases[index] = rng:NextNumber(0, 2 * math.pi)
	end
	-- Material je Voxelsaeule: Zonen vor Flecken, sonst unveraendert. Lesen und Schreiben der Voxel aendert die
	-- Belegung nicht, nur das Material (keine Beulen wie bei ueberlappenden Fuellungen).
	local region = Region3.new(
		Vector3.new(bounds.minX - PAINT_REACH, Ground.TOP - depth - 4, bounds.minZ - PAINT_REACH),
		Vector3.new(bounds.maxX + PAINT_REACH, Ground.TOP + 6, bounds.maxZ + PAINT_REACH)
	):ExpandToGrid(4)
	local materials, occupancies = terrain:ReadVoxels(region, 4)
	local size = materials.Size
	local low = region.CFrame.Position - region.Size / 2
	for ix = 1, size.X do
		local x = low.X + (ix - 0.5) * 4
		for iz = 1, size.Z do
			local z = low.Z + (iz - 0.5) * 4
			local paint: Enum.Material? = nil
			for index, zone in zones do
				local hx, hz = zone.size.X / 2, zone.size.Z / 2
				if Ground.insideZone(x - zone.center.X, z - zone.center.Z, hx, hz, phases[index]) then
					paint = Ground.zoneMaterial(index)
					break
				end
			end
			if paint == nil then
				for _, spot in patches do
					if (x - spot.x) ^ 2 + (z - spot.z) ^ 2 < spot.radius ^ 2 then
						paint = spot.material
						break
					end
				end
			end
			if paint ~= nil then
				for iy = 1, size.Y do
					if occupancies[ix][iy][iz] > 0 then
						materials[ix][iy][iz] = paint
					end
				end
			end
		end
	end
	terrain:WriteVoxels(region, 4, materials, occupancies)
end

return Ground
