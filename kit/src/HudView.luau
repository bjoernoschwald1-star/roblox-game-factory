--!strict
-- Darstellung des HUD: baut aus dem HudModel ein ScreenGui und ruft bei Klick nur Intents auf.
-- Deaktivierte Buttons (z. B. Verkaufen bei leerem Inventar, nicht leistbares Upgrade, nicht freischaltbare Zone)
-- senden keine Absicht. Buttons nutzen GuiButton.Activated (Maus-Klick, Touch-Loslassen und Gamepad-Auswahl).
-- Layout aus kit/src/HudLayout.luau: nur Skalenwerte plus UISizeConstraint, Vorlage nach Seitenverhaeltnis der
-- GUI-Flaeche (ScreenInsets = CoreUISafeInsets, also ohne Topbar); bei Groessenaenderung (Drehen, Fenster) wird
-- neu angeordnet. Texte skalieren (TextScaled mit UITextSizeConstraint) und brechen um statt abzuschneiden.
-- Mindestgroesse der Touch-Buttons: MIN_TOUCH_SIZE Pixel Hoehe (Doku nennt keinen festen Wert; 64 liegt ueber den
-- ueblichen Plattform-Empfehlungen fuer Fingerziele von etwa 44-48 Punkten).
-- Inventar-Anzeige pulsiert kurz bei Aenderung und wird bei vollem Inventar hervorgehoben (uiTokens.highlight).
-- Farben, Schrift und Abstaende kommen aus den uiTokens des Games.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/GuiButton#Activated
--       https://create.roblox.com/docs/reference/engine/classes/ScreenGui#ScreenInsets
--       https://create.roblox.com/docs/reference/engine/classes/UITextSizeConstraint
--       https://create.roblox.com/docs/reference/engine/classes/LayerCollector#ResetOnSpawn
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
}

export type HudView = {
	gui: ScreenGui,
	render: (self: HudView, model: HudModel.Model) -> (),
	press: (self: HudView, action: string) -> boolean,
	buttons: (self: HudView) -> { [string]: TextButton },
	element: (self: HudView, name: string) -> GuiObject?,
	applyLayout: (self: HudView, area: Vector2) -> string,
	destroy: (self: HudView) -> (),
}

local MIN_TOUCH_SIZE = HudLayout.MIN_TOUCH_SIZE

local HudView = {}

HudView.MIN_TOUCH_SIZE = MIN_TOUCH_SIZE

function HudView.new(parent: Instance, intents: Intents, tokens: Tokens?): HudView
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

	local function decorate(target: any)
		target.TextScaled = true
		target.Font = font
		target.TextColor3 = style.text or Color3.fromRGB(255, 255, 255)
		target.BorderSizePixel = 0
		local sizeLimit = Instance.new("UITextSizeConstraint")
		sizeLimit.MaxTextSize = textSize
		sizeLimit.MinTextSize = 10
		sizeLimit.Parent = target
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.2, 0)
		corner.Parent = target
		local padding = Instance.new("UIPadding")
		padding.PaddingLeft = UDim.new(0.04, 0)
		padding.PaddingRight = UDim.new(0.04, 0)
		padding.PaddingTop = UDim.new(0.08, 0)
		padding.PaddingBottom = UDim.new(0.08, 0)
		padding.Parent = target
	end

	local elements: { [string]: GuiObject } = {}
	local function label(name: string, key: string): TextLabel
		local created = Instance.new("TextLabel")
		created.Name = name
		created.BackgroundColor3 = panel
		created.BackgroundTransparency = 0.15
		created.Text = ""
		decorate(created)
		created.Parent = gui
		elements[key] = created
		return created
	end

	local buttonsById: { [string]: TextButton } = {}
	local enabledById: { [string]: boolean } = {}
	local upgradeOrder: { string } = {}
	local currentZone: string? = nil
	local lastArea: Vector2? = nil

	local function button(id: string): TextButton
		local created = Instance.new("TextButton")
		created.Name = id
		created.BackgroundColor3 = accent
		created.AutoButtonColor = true
		decorate(created)
		created.Parent = gui
		buttonsById[id] = created
		return created
	end

	local coins = label("Coins", "coins")
	local inventory = label("Inventory", "inventory")
	local inventoryScale = Instance.new("UIScale")
	inventoryScale.Parent = inventory
	local zoneHint = label("ZoneHint", "zoneHint")
	zoneHint.BackgroundTransparency = 0.35

	-- Aktionen; Buttons und Tests rufen dieselbe Funktion.
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
		elseif string.sub(action, 1, 8) == "upgrade:" then
			return intents:buyUpgrade(string.sub(action, 9))
		end
		return false
	end

	local collectButton = button("collect")
	collectButton.Activated:Connect(function()
		press("collect")
	end)
	local sellButton = button("sell")
	sellButton.Activated:Connect(function()
		press("sell")
	end)
	local unlockButton = button("unlock")
	unlockButton.Activated:Connect(function()
		press("unlock")
	end)

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
		local specs = HudLayout.specs(preset, #upgradeOrder)
		local targets: { [string]: GuiObject } = {
			coins = coins,
			inventory = inventory,
			zoneHint = zoneHint,
			unlock = unlockButton,
			collect = collectButton,
			sell = sellButton,
		}
		for index, dimension in upgradeOrder do
			targets["upgrade" .. index] = buttonsById["upgrade:" .. dimension]
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
			zoneHint.Text = model.zoneText
			currentZone = model.nextZoneId
			unlockButton.Visible = model.nextZoneId ~= nil
			unlockButton.Text = model.unlockText
			setEnabled(unlockButton, model.canUnlock and model.nextZoneId ~= nil)
			collectButton.Text = model.collectText
			setEnabled(collectButton, model.collectEnabled)
			sellButton.Text = model.sellText
			setEnabled(sellButton, model.sellEnabled)

			local added = false
			for _, entry in model.upgrades do
				local id = "upgrade:" .. entry.dimension
				local upgradeButton = buttonsById[id]
				if upgradeButton == nil then
					upgradeButton = button(id)
					table.insert(upgradeOrder, entry.dimension)
					added = true
					local dimension = entry.dimension
					upgradeButton.Activated:Connect(function()
						press("upgrade:" .. dimension)
					end)
				end
				upgradeButton.Text = string.format("%s\n%s · %s", entry.name, entry.levelText, entry.costText)
				setEnabled(upgradeButton, entry.affordable)
			end
			if added then
				applyLayout(lastArea or gui.AbsoluteSize)
			end
		end,

		press = function(_self, action: string): boolean
			return press(action)
		end,

		buttons = function(_self): { [string]: TextButton }
			return table.clone(buttonsById)
		end,

		element = function(_self, name: string): GuiObject?
			if name == "unlock" or name == "collect" or name == "sell" then
				return buttonsById[name]
			end
			local index = tonumber(string.match(name, "^upgrade(%d+)$"))
			if index ~= nil then
				local dimension = upgradeOrder[index]
				return if dimension ~= nil then buttonsById["upgrade:" .. dimension] else nil
			end
			return elements[name]
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
