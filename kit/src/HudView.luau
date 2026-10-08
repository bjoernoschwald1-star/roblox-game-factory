--!strict
-- Darstellung des HUD: baut aus dem HudModel ein ScreenGui und ruft bei Klick nur Intents auf.
-- Kompakt an den Raendern (Layout aus kit/src/HudLayout.luau, Bildschirmmitte frei):
--   Anzeigen "coins" und "inventory" klein neben dem Chat; runde Aktionsknoepfe "collect" und "sell" unten rechts;
--   Rand-Knoepfe "unlock" (zeigt die naechste Zonen-Bedingung) und "upgrades" (oeffnet das Upgrade-Fenster).
--   Upgrade-Fenster "UpgradeWindow": mittig, nur auf Knopfdruck; enthaelt je Upgrade einen Knopf "upgrade:<dim>"
--   und "upgradesClose". Aktionen "upgrades" (umschalten) und "upgradesClose" senden keine Absicht.
--   Sammelalbum (optional, vierter Parameter album = AlbumView.Options): Rand-Knopf "album" (nur sichtbar, wenn der
--   Schnappschuss ein Album hat) oeffnet das AlbumWindow, "albumClose" schliesst; renderAlbum(AlbumModel) fuellt es.
--   Upgrade- und Album-Fenster schliessen sich gegenseitig. Beides sendet keine Absicht.
--   Prestige: Rand-Knopf "prestige" (nur sichtbar, wenn moeglich) oeffnet das Bestaetigungsfenster
--   "PrestigeDialog" (Platz des Upgrade-Fensters) mit Verlust und Gewinn; erst "prestigeConfirm" sendet die
--   Absicht, "prestigeCancel" schliesst ohne Absicht.
-- Deaktivierte Knoepfe (z. B. Verkaufen bei leerem Inventar, nicht leistbares Upgrade, nicht freischaltbare Zone,
-- Einsammeln bei voller Ladung) senden keine Absicht. GuiButton.Activated deckt Maus, Touch und Gamepad ab.
-- Groessen: Skalenwerte plus UISizeConstraint (feste Pixelgroesse je Vorlage: am PC klein, auf dem Handy
-- daumengross); bei Groessenaenderung (Drehen, Fenster) wird neu angeordnet. Texte skalieren (TextScaled mit
-- UITextSizeConstraint). Inventar-Anzeige pulsiert bei Aenderung und wird bei voller Ladung hervorgehoben.
-- Farben und Schrift kommen aus den uiTokens des Games.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/GuiButton#Activated
--       https://create.roblox.com/docs/reference/engine/classes/ScreenGui#ScreenInsets
--       https://create.roblox.com/docs/reference/engine/classes/UITextSizeConstraint
--       https://create.roblox.com/docs/reference/engine/classes/UIListLayout
local AlbumModel = require(script.Parent.AlbumModel)
local AlbumView = require(script.Parent.AlbumView)
local HudLayout = require(script.Parent.HudLayout)
local HudModel = require(script.Parent.HudModel)

export type Tokens = {
	background: Color3?,
	panel: Color3?,
	text: Color3?,
	accent: Color3?,
	disabled: Color3?,
	highlight: Color3?,
	highlightText: Color3?,
	font: Enum.Font?,
	textSize: number?,
	padding: number?,
}

export type Intents = {
	collect: (self: any) -> boolean,
	sell: (self: any) -> boolean,
	buyUpgrade: (self: any, dimension: string) -> boolean,
	unlockZone: (self: any, zoneId: string) -> boolean,
	prestige: ((self: any) -> boolean)?,
}

export type HudView = {
	gui: ScreenGui,
	render: (self: HudView, model: HudModel.Model) -> (),
	renderAlbum: (self: HudView, model: AlbumModel.Model) -> (),
	albumOpen: (self: HudView) -> boolean,
	press: (self: HudView, action: string) -> boolean,
	buttons: (self: HudView) -> { [string]: TextButton },
	element: (self: HudView, name: string) -> GuiObject?,
	windowOpen: (self: HudView) -> boolean,
	dialogOpen: (self: HudView) -> boolean,
	applyLayout: (self: HudView, area: Vector2) -> string,
	destroy: (self: HudView) -> (),
}

local HudView = {}

HudView.MIN_TOUCH_SIZE = HudLayout.MIN_TOUCH_SIZE

function HudView.new(parent: Instance, intents: Intents, tokens: Tokens?, album: AlbumView.Options?): HudView
	local style: Tokens = tokens or {}
	local textSize = style.textSize or 22
	local font = style.font or Enum.Font.GothamBold
	local panel = style.panel or Color3.fromRGB(40, 40, 40)
	local accent = style.accent or Color3.fromRGB(70, 130, 200)
	local disabled = style.disabled or Color3.fromRGB(90, 90, 90)
	local highlight = style.highlight or Color3.fromRGB(255, 200, 40)
	local textColor = style.text or Color3.fromRGB(255, 255, 255)
	-- Dunkle Schrift auf der hellen Hervorhebung (Kontrast).
	local highlightText = style.highlightText or Color3.fromRGB(30, 30, 30)
	local TweenService = game:GetService("TweenService")

	local gui = Instance.new("ScreenGui")
	gui.Name = "FactoryHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets

	local function decorate(target: any, round: boolean?)
		target.TextScaled = true
		target.Font = font
		target.TextColor3 = textColor
		target.BorderSizePixel = 0
		local sizeLimit = Instance.new("UITextSizeConstraint")
		sizeLimit.MaxTextSize = textSize
		sizeLimit.MinTextSize = 9
		sizeLimit.Parent = target
		local corner = Instance.new("UICorner")
		corner.CornerRadius = if round then UDim.new(0.5, 0) else UDim.new(0.25, 0)
		corner.Parent = target
		local padding = Instance.new("UIPadding")
		-- Runde Knoepfe: wenig Rand, damit der Text im Kreis gross bleibt.
		local inset = if round then 0.1 else 0.06
		padding.PaddingLeft = UDim.new(inset, 0)
		padding.PaddingRight = UDim.new(inset, 0)
		padding.PaddingTop = UDim.new(0.12, 0)
		padding.PaddingBottom = UDim.new(0.12, 0)
		padding.Parent = target
	end

	local elements: { [string]: GuiObject } = {}
	local function label(name: string, key: string): TextLabel
		local created = Instance.new("TextLabel")
		created.Name = name
		created.BackgroundColor3 = panel
		created.BackgroundTransparency = 0.25
		created.Text = ""
		decorate(created)
		created.Parent = gui
		elements[key] = created
		return created
	end

	local buttonsById: { [string]: TextButton } = {}
	local enabledById: { [string]: boolean } = {}
	local currentZone: string? = nil
	local lastArea: Vector2? = nil

	local function button(id: string, parentInstance: Instance, round: boolean?): TextButton
		local created = Instance.new("TextButton")
		created.Name = id
		created.BackgroundColor3 = accent
		created.AutoButtonColor = true
		decorate(created, round)
		created.Parent = parentInstance
		buttonsById[id] = created
		return created
	end

	local coins = label("Coins", "coins")
	local inventory = label("Inventory", "inventory")
	local inventoryScale = Instance.new("UIScale")
	inventoryScale.Parent = inventory

	-- Upgrade-Fenster (modal, mittig)
	local window = Instance.new("Frame")
	window.Name = "UpgradeWindow"
	window.BackgroundColor3 = panel
	window.BackgroundTransparency = 0.1
	window.Visible = false
	window.Parent = gui
	elements.window = window
	local windowCorner = Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(0.06, 0)
	windowCorner.Parent = window
	local list = Instance.new("Frame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromScale(0.05, 0.2)
	list.Size = UDim2.fromScale(0.9, 0.76)
	list.Parent = window
	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0.03, 0)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromScale(0.05, 0.03)
	title.Size = UDim2.fromScale(0.7, 0.13)
	title.TextXAlignment = Enum.TextXAlignment.Left
	decorate(title)
	title.Parent = window

	-- Sammelalbum (modal, eigener Platz albumWindow)
	local albumOptions: AlbumView.Options = table.clone(album or {})
	albumOptions.panel = albumOptions.panel or panel
	albumOptions.text = albumOptions.text or textColor
	albumOptions.accent = albumOptions.accent or highlight
	albumOptions.font = albumOptions.font or font
	local albumView = AlbumView.new(gui, albumOptions)
	elements.albumWindow = albumView.frame

	-- Bestaetigungsfenster fuer Prestige (modal, Platz des Upgrade-Fensters)
	local dialog = Instance.new("Frame")
	dialog.Name = "PrestigeDialog"
	dialog.BackgroundColor3 = panel
	dialog.BackgroundTransparency = 0.05
	dialog.Visible = false
	dialog.Parent = gui
	elements.dialog = dialog
	local dialogCorner = Instance.new("UICorner")
	dialogCorner.CornerRadius = UDim.new(0.06, 0)
	dialogCorner.Parent = dialog
	local function dialogLine(name: string, y: number, h: number, color: Color3?): TextLabel
		local line = Instance.new("TextLabel")
		line.Name = name
		line.BackgroundTransparency = 1
		line.Position = UDim2.fromScale(0.06, y)
		line.Size = UDim2.fromScale(0.88, h)
		decorate(line)
		if color ~= nil then
			line.TextColor3 = color
		end
		line.Parent = dialog
		return line
	end
	local dialogTitle = dialogLine("Title", 0.04, 0.16)
	local dialogLose = dialogLine("Lose", 0.24, 0.22, Color3.fromRGB(255, 150, 140))
	local dialogGain = dialogLine("Gain", 0.48, 0.2, highlight)

	-- Aktionen; Knoepfe und Tests rufen dieselbe Funktion.
	local function press(action: string): boolean
		if enabledById[action] == false then
			return false
		end
		if action == "collect" then
			return intents:collect()
		elseif action == "sell" then
			return intents:sell()
		elseif action == "unlock" then
			return currentZone ~= nil and intents:unlockZone(currentZone :: string)
		elseif action == "upgrades" then
			-- Es ist immer hoechstens ein Fenster offen (Upgrades, Album, Schmelze).
			window.Visible = not window.Visible
			albumView:setOpen(false)
			dialog.Visible = false
			return true
		elseif action == "album" then
			albumView:setOpen(not albumView:isOpen())
			window.Visible = false
			dialog.Visible = false
			return true
		elseif action == "albumClose" then
			albumView:setOpen(false)
			return true
		elseif action == "upgradesClose" then
			window.Visible = false
			return true
		elseif action == "prestige" then
			window.Visible = false
			albumView:setOpen(false)
			dialog.Visible = true
			return true
		elseif action == "prestigeCancel" then
			dialog.Visible = false
			return true
		elseif action == "prestigeConfirm" then
			dialog.Visible = false
			local send = intents.prestige
			return send ~= nil and send(intents)
		elseif string.sub(action, 1, 8) == "upgrade:" then
			return intents:buyUpgrade(string.sub(action, 9))
		end
		return false
	end

	local function connect(target: TextButton, action: string)
		target.Activated:Connect(function()
			press(action)
		end)
	end
	local collectButton = button("collect", gui, true)
	connect(collectButton, "collect")
	local sellButton = button("sell", gui, true)
	connect(sellButton, "sell")
	local unlockButton = button("unlock", gui)
	connect(unlockButton, "unlock")
	local upgradesButton = button("upgrades", gui)
	connect(upgradesButton, "upgrades")
	local closeButton = button("upgradesClose", window, true)
	closeButton.Text = "X"
	closeButton.Position = UDim2.fromScale(0.84, 0.03)
	closeButton.Size = UDim2.fromScale(0.11, 0.13)
	closeButton.BackgroundColor3 = disabled
	connect(closeButton, "upgradesClose")
	local albumButton = button("album", gui)
	albumButton.Visible = false
	connect(albumButton, "album")
	buttonsById.albumClose = albumView.closeButton
	connect(albumView.closeButton, "albumClose")
	local prestigeButton = button("prestige", gui)
	prestigeButton.Visible = false
	connect(prestigeButton, "prestige")
	local confirmButton = button("prestigeConfirm", dialog)
	confirmButton.Position = UDim2.fromScale(0.06, 0.74)
	confirmButton.Size = UDim2.fromScale(0.42, 0.2)
	connect(confirmButton, "prestigeConfirm")
	local cancelButton = button("prestigeCancel", dialog)
	cancelButton.Position = UDim2.fromScale(0.52, 0.74)
	cancelButton.Size = UDim2.fromScale(0.42, 0.2)
	cancelButton.BackgroundColor3 = disabled
	connect(cancelButton, "prestigeCancel")

	local function setEnabled(target: TextButton, enabled: boolean)
		enabledById[target.Name] = enabled
		target.Active = enabled
		target.AutoButtonColor = enabled
		target.BackgroundColor3 = if enabled then accent else disabled
	end

	-- Ordnet alle Elemente fuer die GUI-Flaeche area an; liefert die gewaehlte Vorlage.
	local function applyLayout(area: Vector2): string
		lastArea = area
		local preset = HudLayout.presetFor(area)
		local specs = HudLayout.specs(preset, nil, area)
		local targets: { [string]: GuiObject } = {
			coins = coins,
			inventory = inventory,
			unlock = unlockButton,
			upgrades = upgradesButton,
			album = albumButton,
			prestige = prestigeButton,
			collect = collectButton,
			sell = sellButton,
			window = window,
		}
		local windowSpec = specs.window
		if windowSpec ~= nil then
			HudLayout.apply(dialog, windowSpec)
		end
		local albumSpec = specs.albumWindow
		if albumSpec ~= nil then
			albumView:applySpec(albumSpec)
		end
		for name, target in targets do
			local s = specs[name]
			if s ~= nil then
				HudLayout.apply(target, s)
			end
		end
		return preset
	end

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		applyLayout(gui.AbsoluteSize)
	end)

	local lastInventoryText: string? = nil
	local view: HudView = {
		gui = gui,

		render = function(_self, model: HudModel.Model)
			coins.Text = model.coinsText
			if lastInventoryText ~= nil and lastInventoryText ~= model.inventoryText then
				inventoryScale.Scale = 1.15
				TweenService:Create(inventoryScale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
			end
			lastInventoryText = model.inventoryText
			inventory.Text = model.inventoryText
			inventory.BackgroundColor3 = if model.full then highlight else panel
			inventory.TextColor3 = if model.full then highlightText else textColor
			currentZone = model.nextZoneId
			-- Ein Knopf am Rand: zeigt die Bedingung der naechsten Zone, freischaltbar sobald erfuellt.
			unlockButton.Visible = model.nextZoneId ~= nil
			unlockButton.Text = model.zoneText
			setEnabled(unlockButton, model.canUnlock and model.nextZoneId ~= nil)
			upgradesButton.Text = model.upgradesText
			title.Text = model.upgradesText
			collectButton.Text = model.collectText
			setEnabled(collectButton, model.collectEnabled)
			sellButton.Text = model.sellText
			setEnabled(sellButton, model.sellEnabled)
			-- Prestige-Knopf und Bestaetigen in der Hervorhebungsfarbe (wichtige, seltene Entscheidung).
			prestigeButton.Visible = model.prestigeVisible
			prestigeButton.Text = model.prestigeText
			prestigeButton.BackgroundColor3 = highlight
			prestigeButton.TextColor3 = highlightText
			confirmButton.BackgroundColor3 = highlight
			confirmButton.TextColor3 = highlightText
			dialogTitle.Text = model.prestigeTitle
			dialogLose.Text = model.prestigeLose
			dialogGain.Text = model.prestigeGain
			confirmButton.Text = model.prestigeConfirm
			cancelButton.Text = model.prestigeCancel
			-- Nicht mehr moeglich (z. B. nach dem Zuruecksetzen): Fenster schliessen.
			if not model.prestigeVisible then
				dialog.Visible = false
			end

			local count = #model.upgrades
			for index, entry in model.upgrades do
				local id = "upgrade:" .. entry.dimension
				local upgradeButton = buttonsById[id]
				if upgradeButton == nil then
					upgradeButton = button(id, list)
					connect(upgradeButton, id)
				end
				upgradeButton.LayoutOrder = index
				upgradeButton.Size = UDim2.fromScale(1, 0.9 / math.max(count, 1) - 0.03)
				upgradeButton.Text = string.format("%s\n%s · %s", entry.name, entry.levelText, entry.costText)
				setEnabled(upgradeButton, entry.affordable)
			end
			if lastArea == nil then
				applyLayout(gui.AbsoluteSize)
			end
		end,

		press = function(_self, action: string): boolean
			return press(action)
		end,

		buttons = function(_self): { [string]: TextButton }
			return table.clone(buttonsById)
		end,

		element = function(_self, name: string): GuiObject?
			return buttonsById[name] or elements[name]
		end,

		windowOpen = function(_self): boolean
			return window.Visible
		end,

		dialogOpen = function(_self): boolean
			return dialog.Visible
		end,

		renderAlbum = function(_self, model: AlbumModel.Model)
			albumButton.Visible = model.visible
			albumButton.Text = model.buttonText
			if not model.visible then
				albumView:setOpen(false)
				return
			end
			albumView:render(model)
		end,

		albumOpen = function(_self): boolean
			return albumView:isOpen()
		end,

		applyLayout = function(_self, area: Vector2): string
			return applyLayout(area)
		end,

		destroy = function(_self)
			gui:Destroy()
		end,
	}
	applyLayout(gui.AbsoluteSize)
	gui.Parent = parent
	return view
end

return HudView
