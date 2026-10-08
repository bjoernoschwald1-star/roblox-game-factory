--!strict
-- Darstellung des Sammelalbums: modales Fenster "AlbumWindow" (Platz aus HudLayout "albumWindow") mit Titel,
-- Fortschritt "x / y", Schliessen-Knopf "albumClose" und je Gruppe einer Reihe: oben Name, Reihen-Fortschritt und
-- Belohnungstext, darunter die Zellen je Eintrag (passt auch in das kleinste Fenster von 220 px Breite). Reihen liegen in einem ScrollingFrame (feste Zeilenhoehe), damit die
-- Vorschaubilder auch auf kleinen Handy-Flaechen erkennbar bleiben.
-- Zelle "cell:<entryId>": ViewportFrame mit einer Kopie des Vorschau-Modells (options.preview(entryId), vom Game);
-- gefunden = in Farbe mit Rahmen in der Seltenheitsfarbe, fehlend = dunkle Silhouette (alle Teile der Kopie in
-- SILHOUETTE, Neon aus) auf hellerem Grund; ImageColor3 wuerde auch den Hintergrund abdunkeln. Ohne Modell
-- bleibt die Zelle eine farbige bzw. dunkle Flaeche. Sendet nie Absichten (Album ist nur Anzeige).
-- Meshes, die noch nirgends in der Welt zu sehen waren, sind auf dem Client nicht geladen; ein ViewportFrame
-- zeichnet sie dann nicht (im Spieltest fehlten so Teile seltener Items). Daher laedt jede Zelle ihre Kopie mit
-- ContentProvider:PreloadAsync und haengt sie danach neu ein; beim Oeffnen werden alle Kopien neu eingehaengt.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/ViewportFrame
--       https://create.roblox.com/docs/reference/engine/classes/ContentProvider#PreloadAsync
--       https://create.roblox.com/docs/reference/engine/classes/ScrollingFrame
local AlbumModel = require(script.Parent.AlbumModel)
local HudLayout = require(script.Parent.HudLayout)

export type Options = {
	preview: ((entryId: string) -> Model?)?,
	rarityColors: { [string]: Color3 }?,
	panel: Color3?,
	text: Color3?,
	accent: Color3?,
	font: Enum.Font?,
}

export type AlbumView = {
	frame: Frame,
	render: (self: AlbumView, model: AlbumModel.Model) -> (),
	setOpen: (self: AlbumView, open: boolean) -> (),
	isOpen: (self: AlbumView) -> boolean,
	cell: (self: AlbumView, entryId: string) -> ViewportFrame?,
	applySpec: (self: AlbumView, spec: HudLayout.Spec) -> (),
	closeButton: TextButton,
}

local ROW_HEIGHT = 66
local LINE_HEIGHT = 18
local CELL = ROW_HEIGHT - LINE_HEIGHT - 6
local SILHOUETTE = Color3.fromRGB(28, 22, 20)
-- Hintergrund der Zellen: fehlende Teile als dunkle Silhouette auf hellerem Grund, gefundene auf dunklem Grund.
local FOUND_BACKGROUND = Color3.fromRGB(30, 22, 18)
local MISSING_BACKGROUND = Color3.fromRGB(150, 128, 110)

local AlbumView = {}

AlbumView.ROW_HEIGHT = ROW_HEIGHT
AlbumView.SILHOUETTE = SILHOUETTE

local function label(name: string, parent: Instance, font: Enum.Font, color: Color3, maxSize: number): TextLabel
	local created = Instance.new("TextLabel")
	created.Name = name
	created.BackgroundTransparency = 1
	created.TextScaled = true
	created.Font = font
	created.TextColor3 = color
	created.TextXAlignment = Enum.TextXAlignment.Left
	local limit = Instance.new("UITextSizeConstraint")
	limit.MaxTextSize = maxSize
	limit.MinTextSize = 8
	limit.Parent = created
	created.Parent = parent
	return created
end

-- Kamera so setzen, dass das Modell die Zelle fuellt (schraeg von vorn oben).
local function frameModel(viewport: ViewportFrame, model: Model)
	local cframe, size = model:GetBoundingBox()
	local radius = math.max(size.Magnitude / 2, 0.1)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	local distance = radius / math.tan(math.rad(camera.FieldOfView / 2)) * 1.05
	local direction = Vector3.new(0.6, 0.45, 1).Unit
	camera.CFrame = CFrame.lookAt(cframe.Position + direction * distance, cframe.Position)
	camera.Parent = viewport
	viewport.CurrentCamera = camera
end

function AlbumView.new(parent: Instance, options: Options?): AlbumView
	local opts: Options = options or {}
	local font = opts.font or Enum.Font.GothamBold
	local textColor = opts.text or Color3.new(1, 1, 1)
	local panel = opts.panel or Color3.fromRGB(40, 40, 40)
	local accent = opts.accent or Color3.fromRGB(255, 200, 40)
	local colors = opts.rarityColors or {}

	local frame = Instance.new("Frame")
	frame.Name = "AlbumWindow"
	frame.BackgroundColor3 = panel
	frame.BackgroundTransparency = 0.05
	frame.Visible = false
	frame.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	local title = label("Title", frame, font, textColor, 24)
	title.Position = UDim2.fromOffset(12, 6)
	title.Size = UDim2.new(0.55, -12, 0, 28)
	local progress = label("Progress", frame, font, accent, 22)
	progress.Position = UDim2.new(0.55, 0, 0, 6)
	progress.Size = UDim2.new(0.45, -52, 0, 28)
	progress.TextXAlignment = Enum.TextXAlignment.Right

	local close = Instance.new("TextButton")
	close.Name = "albumClose"
	close.Text = "X"
	close.Font = font
	close.TextScaled = true
	close.TextColor3 = textColor
	close.BackgroundColor3 = Color3.fromRGB(110, 100, 95)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 6)
	close.Size = UDim2.fromOffset(32, 28)
	close.Parent = frame
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0.5, 0)
	closeCorner.Parent = close

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Rows"
	scroller.BackgroundTransparency = 1
	scroller.BorderSizePixel = 0
	scroller.Position = UDim2.fromOffset(8, 40)
	scroller.Size = UDim2.new(1, -16, 1, -48)
	scroller.ScrollBarThickness = 6
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.CanvasSize = UDim2.new()
	scroller.ScrollingDirection = Enum.ScrollingDirection.Y
	scroller.Parent = frame
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 4)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroller

	local rows: { [string]: Frame } = {}
	local cells: { [string]: ViewportFrame } = {}
	-- Je Zelle die Teile der Modellkopie mit Originalfarbe und -material (fuer den Wechsel zur Silhouette).
	type Original = { part: BasePart, color: Color3, material: Enum.Material }
	local originals: { [string]: { Original } } = {}
	local shownFound: { [string]: boolean } = {}

	local function cellFor(rowFrame: Frame, entryId: string, index: number): ViewportFrame
		local existing = cells[entryId]
		if existing ~= nil then
			return existing
		end
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "cell:" .. entryId
		viewport.BackgroundColor3 = Color3.fromRGB(25, 18, 15)
		viewport.BackgroundTransparency = 0.2
		viewport.Ambient = Color3.fromRGB(170, 160, 150)
		viewport.LightColor = Color3.fromRGB(255, 240, 220)
		viewport.LightDirection = Vector3.new(-0.5, -1, -0.6)
		viewport.LayoutOrder = index
		viewport.Size = UDim2.fromOffset(CELL, CELL)
		local cellCorner = Instance.new("UICorner")
		cellCorner.CornerRadius = UDim.new(0.15, 0)
		cellCorner.Parent = viewport
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 2
		stroke.Transparency = 1
		stroke.Parent = viewport
		local template = if opts.preview ~= nil then opts.preview(entryId) else nil
		if template ~= nil then
			local copy = template:Clone()
			local parts: { Original } = {}
			for _, part in copy:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
					table.insert(parts, { part = part, color = part.Color, material = part.Material })
				end
			end
			originals[entryId] = parts
			copy.Parent = viewport
			frameModel(viewport, copy)
			task.defer(function()
				pcall(function()
					game:GetService("ContentProvider"):PreloadAsync({ copy })
				end)
				if copy.Parent == viewport then
					copy.Parent = nil
					task.defer(function()
						if viewport.Parent ~= nil then
							copy.Parent = viewport
						end
					end)
				end
			end)
		end
		viewport.Parent = rowFrame:FindFirstChild("Cells")
		cells[entryId] = viewport
		return viewport
	end

	local function rowFor(groupId: string, index: number): Frame
		local existing = rows[groupId]
		if existing ~= nil then
			existing.LayoutOrder = index
			return existing
		end
		local rowFrame = Instance.new("Frame")
		rowFrame.Name = "row:" .. groupId
		rowFrame.BackgroundTransparency = 1
		rowFrame.LayoutOrder = index
		rowFrame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		rowFrame.Parent = scroller
		local name = label("Name", rowFrame, font, textColor, 16)
		name.Size = UDim2.new(0.38, -4, 0, LINE_HEIGHT)
		local rowProgress = label("Progress", rowFrame, font, accent, 16)
		rowProgress.Position = UDim2.fromScale(0.38, 0)
		rowProgress.Size = UDim2.new(0.14, -4, 0, LINE_HEIGHT)
		local reward = label("Reward", rowFrame, font, textColor, 14)
		reward.Position = UDim2.fromScale(0.52, 0)
		reward.Size = UDim2.new(0.48, 0, 0, LINE_HEIGHT)
		reward.TextXAlignment = Enum.TextXAlignment.Right
		local cellRow = Instance.new("Frame")
		cellRow.Name = "Cells"
		cellRow.BackgroundTransparency = 1
		cellRow.Position = UDim2.fromOffset(0, LINE_HEIGHT + 3)
		cellRow.Size = UDim2.new(1, 0, 0, CELL)
		cellRow.Parent = rowFrame
		local cellLayout = Instance.new("UIListLayout")
		cellLayout.FillDirection = Enum.FillDirection.Horizontal
		cellLayout.Padding = UDim.new(0, 4)
		cellLayout.SortOrder = Enum.SortOrder.LayoutOrder
		cellLayout.Parent = cellRow
		rows[groupId] = rowFrame
		return rowFrame
	end

	local view: AlbumView = {
		frame = frame,
		closeButton = close,

		render = function(_self, model: AlbumModel.Model)
			title.Text = model.title
			progress.Text = model.progressText
			for index, row in model.rows do
				local rowFrame = rowFor(row.groupId, index)
				local name = rowFrame:FindFirstChild("Name") :: TextLabel
				name.Text = row.name
				local rowProgress = rowFrame:FindFirstChild("Progress") :: TextLabel
				rowProgress.Text = row.progressText
				rowProgress.TextColor3 = if row.done then accent else textColor
				local reward = rowFrame:FindFirstChild("Reward") :: TextLabel
				reward.Text = row.rewardText
				reward.TextColor3 = if row.done then accent else textColor
				for cellIndex, cellModel in row.cells do
					local viewport = cellFor(rowFrame, cellModel.entryId, cellIndex)
					if shownFound[cellModel.entryId] ~= cellModel.found then
						shownFound[cellModel.entryId] = cellModel.found
						for _, original in originals[cellModel.entryId] or {} do
							original.part.Color = if cellModel.found then original.color else SILHOUETTE
							original.part.Material = if cellModel.found
								then original.material
								else Enum.Material.SmoothPlastic
						end
					end
					viewport.BackgroundColor3 = if cellModel.found then FOUND_BACKGROUND else MISSING_BACKGROUND
					local stroke = viewport:FindFirstChildOfClass("UIStroke") :: UIStroke
					stroke.Color = colors[cellModel.rarity or ""] or accent
					stroke.Transparency = if cellModel.found then 0 else 1
				end
			end
		end,

		setOpen = function(_self, open: boolean)
			-- Beim Oeffnen alle Modelle neu einhaengen: Im Spieltest zeichnete ein ViewportFrame Farbwechsel bzw.
			-- erst spaeter geladene Meshes sonst nicht neu (leere Zelle trotz gefundenem Teil).
			if open and not frame.Visible then
				for _, viewport in cells do
					local model = viewport:FindFirstChildWhichIsA("Model")
					if model ~= nil then
						-- Erst im naechsten Schritt wieder einhaengen; im selben Frame zaehlt es nicht als Neuzugang.
						model.Parent = nil
						task.defer(function()
							if viewport.Parent ~= nil then
								model.Parent = viewport
							end
						end)
					end
				end
			end
			frame.Visible = open
		end,

		isOpen = function(_self): boolean
			return frame.Visible
		end,

		cell = function(_self, entryId: string): ViewportFrame?
			return cells[entryId]
		end,

		applySpec = function(_self, spec: HudLayout.Spec)
			HudLayout.apply(frame, spec)
		end,
	}
	return view
end

return AlbumView
