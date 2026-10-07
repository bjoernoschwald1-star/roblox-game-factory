--!strict
-- Darstellung des HUD: baut aus dem HudModel ein ScreenGui und ruft bei Klick nur Intents auf.
-- Deaktivierte Buttons (z. B. Verkaufen bei leerem Inventar) senden keine Absicht.
-- Buttons nutzen GuiButton.Activated (Maus-Klick, Touch-Loslassen und Gamepad-Auswahl in einem Event).
-- Mindestgroesse der Touch-Buttons: MIN_TOUCH_SIZE Pixel in Breite und Hoehe. Die Roblox-Doku nennt keinen festen
-- Wert; 64 liegt ueber den ueblichen Plattform-Empfehlungen fuer Fingerziele (etwa 44-48 Punkte) und bleibt
-- auch auf kleinen Telefonen mit Daumen sicher treffbar.
-- Farben, Schrift und Abstaende kommen aus den uiTokens des Games.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/GuiButton#Activated
--       https://create.roblox.com/docs/reference/engine/classes/LayerCollector#ResetOnSpawn
local HudModel = require(script.Parent.HudModel)

export type Tokens = {
	background: Color3?,
	panel: Color3?,
	text: Color3?,
	accent: Color3?,
	disabled: Color3?,
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
	destroy: (self: HudView) -> (),
}

local MIN_TOUCH_SIZE = 64

local HudView = {}

HudView.MIN_TOUCH_SIZE = MIN_TOUCH_SIZE

function HudView.new(parent: Instance, intents: Intents, tokens: Tokens?): HudView
	local style: Tokens = tokens or {}
	local padding = style.padding or 12
	local textSize = style.textSize or 22
	local font = style.font or Enum.Font.GothamBold

	local gui = Instance.new("ScreenGui")
	gui.Name = "FactoryHud"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false

	local function label(name: string, position: UDim2, size: UDim2): TextLabel
		local created = Instance.new("TextLabel")
		created.Name = name
		created.Position = position
		created.Size = size
		created.BackgroundColor3 = style.panel or Color3.fromRGB(40, 40, 40)
		created.BackgroundTransparency = 0.2
		created.TextColor3 = style.text or Color3.fromRGB(255, 255, 255)
		created.Font = font
		created.TextSize = textSize
		created.TextWrapped = true
		created.Text = ""
		created.Parent = gui
		return created
	end

	local buttonsById: { [string]: TextButton } = {}
	local enabledById: { [string]: boolean } = {}
	local currentZone: string? = nil

	local function button(id: string, position: UDim2, width: number): TextButton
		local created = Instance.new("TextButton")
		created.Name = id
		created.Position = position
		created.Size = UDim2.fromOffset(math.max(width, MIN_TOUCH_SIZE), MIN_TOUCH_SIZE)
		created.BackgroundColor3 = style.accent or Color3.fromRGB(70, 130, 200)
		created.TextColor3 = style.text or Color3.fromRGB(255, 255, 255)
		created.Font = font
		created.TextSize = textSize
		created.TextWrapped = true
		created.AutoButtonColor = true
		created.Parent = gui
		buttonsById[id] = created
		return created
	end

	local coins = label("Coins", UDim2.fromOffset(padding, padding), UDim2.fromOffset(260, 44))
	local inventory = label("Inventory", UDim2.fromOffset(padding, padding * 2 + 44), UDim2.fromOffset(260, 44))
	local zoneHint = label("ZoneHint", UDim2.new(0.5, -200, 0, padding), UDim2.fromOffset(400, 44))

	local view: HudView

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

	local collectButton = button(
		"collect",
		UDim2.new(1, -(MIN_TOUCH_SIZE * 2 + padding * 2), 1, -(MIN_TOUCH_SIZE * 2 + padding * 2)),
		MIN_TOUCH_SIZE * 2
	)
	collectButton.Activated:Connect(function()
		press("collect")
	end)
	local sellButton = button(
		"sell",
		UDim2.new(1, -(MIN_TOUCH_SIZE * 2 + padding * 2), 1, -(MIN_TOUCH_SIZE + padding)),
		MIN_TOUCH_SIZE * 2
	)
	sellButton.Activated:Connect(function()
		press("sell")
	end)
	local unlockButton = button("unlock", UDim2.new(0.5, -110, 0, padding * 2 + 44), 220)
	unlockButton.Activated:Connect(function()
		press("unlock")
	end)

	local function setEnabled(target: TextButton, enabled: boolean)
		enabledById[target.Name] = enabled
		target.Active = enabled
		target.AutoButtonColor = enabled
		target.BackgroundColor3 = if enabled
			then style.accent or Color3.fromRGB(70, 130, 200)
			else style.disabled or Color3.fromRGB(90, 90, 90)
	end

	view = {
		gui = gui,

		render = function(_self, model: HudModel.Model)
			coins.Text = model.coinsText
			inventory.Text = model.inventoryText
			zoneHint.Text = model.zoneText
			currentZone = model.nextZoneId
			unlockButton.Visible = model.nextZoneId ~= nil
			unlockButton.Text = model.zoneText
			setEnabled(unlockButton, model.canUnlock)
			collectButton.Text = model.collectText
			sellButton.Text = model.sellText
			setEnabled(sellButton, model.sellEnabled)

			for index, entry in model.upgrades do
				local id = "upgrade:" .. entry.dimension
				local upgradeButton = buttonsById[id]
				if upgradeButton == nil then
					local y = padding * 3 + 88 + (index - 1) * (MIN_TOUCH_SIZE + padding)
					upgradeButton = button(id, UDim2.fromOffset(padding, y), 260)
					local dimension = entry.dimension
					upgradeButton.Activated:Connect(function()
						press("upgrade:" .. dimension)
					end)
				end
				upgradeButton.Text = string.format("%s  %s  %s", entry.name, entry.levelText, entry.costText)
				setEnabled(upgradeButton, entry.affordable)
			end
		end,

		press = function(_self, action: string): boolean
			return press(action)
		end,

		buttons = function(_self): { [string]: TextButton }
			return table.clone(buttonsById)
		end,

		destroy = function(_self)
			gui:Destroy()
		end,
	}
	gui.Parent = parent
	return view
end

return HudView
