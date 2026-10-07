--!strict
-- Darstellung der pro Spieler instanzierten Items im Client. Pro Item-Instanz genau ein lokaler Part im
-- Container (Name = instanceId); nicht mehr vorhandene werden entfernt, bestehende bleiben unveraendert stehen.
-- Die Parts entstehen im LocalScript und werden daher nicht vom Server repliziert. Anchored, ohne Kollision.
--
-- Reine Logik: diff(existingIds, items) -> { add = { item }, remove = { instanceId } }; rarityStyle(rarity, styles)
-- ergaenzt die Seltenheitsdarstellung des Games um DEFAULT_RARITY_STYLES; pose(base, style, phase, now) -> CFrame.
-- Darstellung: reconcile(container, items, assetStyles, itemAssets, options?) mit assetStyles[asset] =
-- { shape = "Block" | "Ball" | "Cylinder", color = Color3, size = number }; itemAssets[itemTypeId] = asset.
-- Unbekannter Asset-Schluessel -> kleiner grauer Wuerfel.
-- Zusammengesetzte Formen (optional assetStyles[asset].parts, z. B. aus Blender erzeugt): Liste von Zeilen
-- { Form, sx, sy, sz, px, py, pz, R00..R22, Farbe (Hex), Material } relativ zum Drehpunkt Mitte unten, dazu
-- height (Studs). Dann ist der Item-Part ein unsichtbarer, verankerter Anker in der Mitte; die sichtbaren
-- Teile haengen per WeldConstraint daran (bewegen sich mit animate und Sog) und liegen in einem Model
-- "Visual", das auch das Highlight umfasst. Keine Unions, keine Assets. options.rarities[itemTypeId] = Seltenheit,
-- options.rarityStyles = Darstellung je Seltenheit (Game), options.limits = Effekt-Deckel,
-- options.onRemove(part) -> true uebernimmt einen entfernten Part (z. B. Sog-Animation) statt ihn zu zerstoeren.
-- animate(container, now) bewegt Items mit Schwebe-/Drehbewegung (Aufruf je Frame aus dem Client).
--
-- Seltenheit ohne Assets: Groesse (scale), Material (Neon fuer legendary), Schwebe-/Drehbewegung, Highlight ab rare,
-- PointLight und Sparkles nur ab epic. Effekt-Deckel (gleichzeitig im Container): Die Doku begrenzt Highlights
-- auf 255 pro Client und raet, unbenutzte zu loeschen; jedes Highlight ist ein eigener Render-Durchgang, daher
-- hoechstens 16 (seltene Items sind ohnehin wenige). Lichter: Die Performance-Doku nennt viele, dichte
-- Lichtquellen als Kostentreiber und empfiehlt weniger Lichter ohne Schatten und mit kleiner Range - hier
-- hoechstens 6 PointLights (Shadows aus, Range 8-12) und 6 Sparkles, unabhaengig von der Item-Dichte.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/Highlight
--       https://create.roblox.com/docs/performance-optimization/improve
--       https://create.roblox.com/docs/reference/engine/classes/PointLight
--       https://create.roblox.com/docs/reference/engine/classes/Sparkles

export type Item = {
	instanceId: string,
	itemTypeId: string,
	zoneId: string,
	position: Vector3,
}

export type AssetStyle = {
	shape: string?,
	color: Color3?,
	size: number?,
	parts: { { any } }?,
	height: number?,
}

export type RarityStyle = {
	scale: number?,
	material: string?,
	bob: number?, -- Schwebehoehe in Studs
	spin: number?, -- Grad pro Sekunde
	highlight: boolean?,
	light: boolean?,
	sparkles: boolean?,
	accent: Color3?,
}

export type Limits = {
	highlights: number,
	lights: number,
	sparkles: number,
}

export type Options = {
	rarities: { [string]: string }?,
	rarityStyles: { [string]: RarityStyle }?,
	limits: Limits?,
	onRemove: ((part: BasePart) -> boolean)?,
}

export type Diff = {
	add: { Item },
	remove: { string },
}

local FALLBACK_STYLE: AssetStyle = { shape = "Block", color = Color3.fromRGB(150, 150, 150), size = 1 }
local SHAPES: { [string]: Enum.PartType } = {
	Block = Enum.PartType.Block,
	Ball = Enum.PartType.Ball,
	Cylinder = Enum.PartType.Cylinder,
}

local DEFAULT_RARITY_STYLES: { [string]: RarityStyle } = {
	common = {
		scale = 1,
		material = "SmoothPlastic",
		bob = 0,
		spin = 0,
		highlight = false,
		light = false,
		sparkles = false,
	},
	rare = {
		scale = 1.15,
		material = "Metal",
		bob = 0.25,
		spin = 40,
		highlight = true,
		light = false,
		sparkles = false,
	},
	epic = { scale = 1.3, material = "Metal", bob = 0.35, spin = 70, highlight = true, light = true, sparkles = true },
	legendary = {
		scale = 1.5,
		material = "Neon",
		bob = 0.45,
		spin = 110,
		highlight = true,
		light = true,
		sparkles = true,
	},
}

local DEFAULT_LIMITS: Limits = { highlights = 16, lights = 6, sparkles = 6 }

local ItemView = {}

ItemView.FALLBACK_STYLE = FALLBACK_STYLE
ItemView.DEFAULT_RARITY_STYLES = DEFAULT_RARITY_STYLES
ItemView.DEFAULT_LIMITS = DEFAULT_LIMITS

function ItemView.diff(existingIds: { [string]: boolean }, items: { Item }): Diff
	local wanted: { [string]: boolean } = {}
	local add: { Item } = {}
	for _, item in items do
		wanted[item.instanceId] = true
		if not existingIds[item.instanceId] then
			table.insert(add, item)
		end
	end
	local remove: { string } = {}
	for instanceId in existingIds do
		if not wanted[instanceId] then
			table.insert(remove, instanceId)
		end
	end
	table.sort(remove)
	return { add = add, remove = remove }
end

function ItemView.styleFor(
	item: Item,
	assetStyles: { [string]: AssetStyle },
	itemAssets: { [string]: string }
): AssetStyle
	local asset = itemAssets[item.itemTypeId]
	local style = if asset ~= nil then assetStyles[asset] else nil
	return style or FALLBACK_STYLE
end

-- Vollstaendige Seltenheitsdarstellung: Game-Werte vor Kit-Standard; unbekannte Seltenheit -> common.
function ItemView.rarityStyle(rarity: string?, rarityStyles: { [string]: RarityStyle }?): RarityStyle
	local key = if rarity ~= nil and DEFAULT_RARITY_STYLES[rarity] ~= nil then rarity else "common"
	local merged = table.clone(DEFAULT_RARITY_STYLES[key])
	local custom = if rarityStyles ~= nil then rarityStyles[key] else nil
	if custom ~= nil then
		for field, value in custom :: any do
			(merged :: any)[field] = value
		end
	end
	return merged
end

-- Lage eines schwebenden, sich drehenden Items zum Zeitpunkt now (base = Mittelpunkt in Ruhe).
function ItemView.pose(base: Vector3, bob: number, spin: number, phase: number, now: number): CFrame
	local lift = if bob > 0 then bob * (0.5 + 0.5 * math.sin(now * 2 + phase)) else 0
	return CFrame.new(base + Vector3.new(0, lift, 0)) * CFrame.Angles(0, math.rad(spin * now) + phase, 0)
end

local function countEffects(container: Instance): Limits
	local counts: Limits = { highlights = 0, lights = 0, sparkles = 0 }
	for _, descendant in container:GetDescendants() do
		if descendant:IsA("Highlight") then
			counts.highlights += 1
		elseif descendant:IsA("PointLight") then
			counts.lights += 1
		elseif descendant:IsA("Sparkles") then
			counts.sparkles += 1
		end
	end
	return counts
end

-- Baut die sichtbaren Teile einer zusammengesetzten Form an den Anker (Drehpunkt Mitte unten).
local function buildVisual(anchor: Part, style: AssetStyle, scale: number, bottom: CFrame): Model
	local visual = Instance.new("Model")
	visual.Name = "Visual"
	for index, row in style.parts :: { { any } } do
		local piece = Instance.new("Part")
		piece.Name = "P" .. index
		piece.Shape = SHAPES[row[1]] or Enum.PartType.Block
		piece.Size = Vector3.new(row[2], row[3], row[4]) * scale
		piece.CFrame = bottom
			* CFrame.new(
				row[5] * scale,
				row[6] * scale,
				row[7] * scale,
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
		piece.Color = Color3.fromHex(row[17])
		local found, material = pcall(function()
			return (Enum.Material :: any)[row[18]]
		end)
		piece.Material = if found and typeof(material) == "EnumItem" then material else Enum.Material.SmoothPlastic
		piece.Anchored = false
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.Massless = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = anchor
		weld.Part1 = piece
		weld.Parent = piece
		piece.Parent = visual
	end
	visual.Parent = anchor
	return visual
end

local function createPart(
	item: Item,
	style: AssetStyle,
	rarity: string,
	rarityStyle: RarityStyle,
	container: Instance,
	counts: Limits,
	limits: Limits
): Part
	local scale = rarityStyle.scale or 1
	local size = (style.size or FALLBACK_STYLE.size :: number) * scale
	local composite = style.parts ~= nil and #(style.parts :: { any }) > 0
	local height = if composite then (style.height or size) * scale else size
	local color = style.color or FALLBACK_STYLE.color :: Color3
	local accent = rarityStyle.accent or color
	local part = Instance.new("Part")
	part.Name = item.instanceId
	part.Shape = SHAPES[style.shape or "Block"] or Enum.PartType.Block
	part.Size = Vector3.new(size, size, size)
	part.Color = color
	-- Unbekannter Materialname wirft beim Enum-Zugriff; dann SmoothPlastic.
	local found, material = pcall(function()
		return (Enum.Material :: any)[rarityStyle.material or "SmoothPlastic"]
	end)
	part.Material = if found and typeof(material) == "EnumItem" then material else Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	-- Item-Position ist ein Punkt auf der Oberseite der Zone; das Objekt steht darauf.
	local base = item.position + Vector3.new(0, height / 2, 0)
	part.Position = base
	local visual: Model? = nil
	if composite then
		part.Shape = Enum.PartType.Block
		part.Size = Vector3.new(size, height, size)
		part.Transparency = 1
		visual = buildVisual(part, style, scale, CFrame.new(item.position))
	end
	part:SetAttribute("itemTypeId", item.itemTypeId)
	part:SetAttribute("rarity", rarity)
	local bob = rarityStyle.bob or 0
	local spin = rarityStyle.spin or 0
	if bob > 0 or spin > 0 then
		part:SetAttribute("base", base)
		part:SetAttribute("bob", bob)
		part:SetAttribute("spin", spin)
		part:SetAttribute("phase", (string.len(item.instanceId) * 1.7 + item.position.X) % (2 * math.pi))
	end
	if rarityStyle.highlight and counts.highlights < limits.highlights then
		counts.highlights += 1
		local highlight = Instance.new("Highlight")
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.FillColor = accent
		highlight.FillTransparency = 0.75
		highlight.OutlineColor = accent
		highlight.OutlineTransparency = 0
		if visual ~= nil then
			highlight.Adornee = visual
		end
		highlight.Parent = part
	end
	if rarityStyle.light and counts.lights < limits.lights then
		counts.lights += 1
		local light = Instance.new("PointLight")
		light.Color = accent
		light.Brightness = if rarity == "legendary" then 3 else 2
		light.Range = if rarity == "legendary" then 12 else 8
		light.Shadows = false
		light.Parent = part
	end
	if rarityStyle.sparkles and counts.sparkles < limits.sparkles then
		counts.sparkles += 1
		local sparkles = Instance.new("Sparkles")
		sparkles.SparkleColor = accent
		sparkles.Parent = part
	end
	part.Parent = container
	return part
end

-- Gleicht die Parts im Container mit der Item-Liste ab; liefert den angewandten Diff.
function ItemView.reconcile(
	container: Instance,
	items: { Item },
	assetStyles: { [string]: AssetStyle },
	itemAssets: { [string]: string },
	options: Options?
): Diff
	local opts: Options = options or {}
	local rarities = opts.rarities or {}
	local limits = opts.limits or DEFAULT_LIMITS
	local existing: { [string]: BasePart } = {}
	local existingIds: { [string]: boolean } = {}
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") then
			existing[child.Name] = child
			existingIds[child.Name] = true
		end
	end
	local changes = ItemView.diff(existingIds, items)
	for _, instanceId in changes.remove do
		local part = existing[instanceId]
		local taken = false
		if opts.onRemove ~= nil then
			local ok, result = pcall(opts.onRemove :: (BasePart) -> boolean, part)
			taken = ok and result == true and part.Parent ~= container
		end
		if not taken then
			part:Destroy()
		end
	end
	local counts = countEffects(container)
	for _, item in changes.add do
		local rarity = rarities[item.itemTypeId] or "common"
		createPart(
			item,
			ItemView.styleFor(item, assetStyles, itemAssets),
			rarity,
			ItemView.rarityStyle(rarity, opts.rarityStyles),
			container,
			counts,
			limits
		)
	end
	return changes
end

-- Schwebe-/Drehbewegung aller animierten Items im Container.
function ItemView.animate(container: Instance, now: number)
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") then
			local base = child:GetAttribute("base")
			if typeof(base) == "Vector3" then
				child.CFrame = ItemView.pose(
					base,
					child:GetAttribute("bob") or 0,
					child:GetAttribute("spin") or 0,
					child:GetAttribute("phase") or 0,
					now
				)
			end
		end
	end
end

return ItemView
