--!strict
-- Darstellung der pro Spieler instanzierten Items im Client. Pro Item-Instanz genau ein lokaler Part im
-- Container (Name = instanceId); nicht mehr vorhandene werden entfernt, bestehende bleiben unveraendert stehen.
-- Die Parts entstehen im LocalScript und werden daher nicht vom Server repliziert. Anchored, ohne Kollision.
--
-- Reine Logik: diff(existingIds, items) -> { add = { item }, remove = { instanceId } }.
-- Darstellung: reconcile(container, items, assetStyles, itemAssets) mit assetStyles[asset] =
-- { shape = "Block" | "Ball" | "Cylinder", color = Color3, size = number }; itemAssets[itemTypeId] = asset.
-- Unbekannter Asset-Schluessel -> kleiner grauer Wuerfel.

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

local ItemView = {}

ItemView.FALLBACK_STYLE = FALLBACK_STYLE

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

local function createPart(item: Item, style: AssetStyle, container: Instance): Part
	local size = style.size or FALLBACK_STYLE.size :: number
	local part = Instance.new("Part")
	part.Name = item.instanceId
	part.Shape = SHAPES[style.shape or "Block"] or Enum.PartType.Block
	part.Size = Vector3.new(size, size, size)
	part.Color = style.color or FALLBACK_STYLE.color :: Color3
	part.Material = Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	-- Item-Position ist ein Punkt auf der Oberseite der Zone; das Objekt steht darauf.
	part.Position = item.position + Vector3.new(0, size / 2, 0)
	part:SetAttribute("itemTypeId", item.itemTypeId)
	part.Parent = container
	return part
end

-- Gleicht die Parts im Container mit der Item-Liste ab; liefert den angewandten Diff.
function ItemView.reconcile(
	container: Instance,
	items: { Item },
	assetStyles: { [string]: AssetStyle },
	itemAssets: { [string]: string }
): Diff
	local existing: { [string]: Instance } = {}
	local existingIds: { [string]: boolean } = {}
	for _, child in container:GetChildren() do
		if child:IsA("BasePart") then
			existing[child.Name] = child
			existingIds[child.Name] = true
		end
	end
	local changes = ItemView.diff(existingIds, items)
	for _, instanceId in changes.remove do
		existing[instanceId]:Destroy()
	end
	for _, item in changes.add do
		createPart(item, ItemView.styleFor(item, assetStyles, itemAssets), container)
	end
	return changes
end

return ItemView
