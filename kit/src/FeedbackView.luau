--!strict
-- Darstellung des Feedbacks: kurze Text-Popups (z. B. "+12") ohne Sound-Assets. Die Effekt-Tabelle des Games
-- ordnet jedem Ereignis einen Text-Schluessel und eine Farbe zu; fehlt ein Eintrag, gilt DEFAULT_EFFECTS.
-- Popups verschwinden nach lifetimeSeconds wieder.
local FeedbackModel = require(script.Parent.FeedbackModel)
local Text = require(script.Parent.Text)

export type Effect = {
	textKey: string,
	color: Color3?,
}

export type FeedbackView = {
	show: (self: FeedbackView, events: FeedbackModel.Events, texts: { [string]: string }?) -> { string },
	destroy: (self: FeedbackView) -> (),
}

local DEFAULT_EFFECTS: { [string]: Effect } = {
	collected = { textKey = "feedback_collected", color = Color3.fromRGB(255, 255, 255) },
	earned = { textKey = "feedback_earned", color = Color3.fromRGB(255, 220, 90) },
	upgraded = { textKey = "feedback_upgraded", color = Color3.fromRGB(120, 220, 255) },
	unlocked = { textKey = "feedback_unlocked", color = Color3.fromRGB(140, 255, 140) },
	full = { textKey = "feedback_full", color = Color3.fromRGB(255, 120, 120) },
}
local ORDER = { "collected", "earned", "upgraded", "unlocked", "full" }

local FeedbackView = {}

FeedbackView.DEFAULT_EFFECTS = DEFAULT_EFFECTS

-- Liefert die Popup-Texte zu den Ereignissen in fester Reihenfolge (reine Logik, auch fuer Tests).
function FeedbackView.messages(
	events: FeedbackModel.Events,
	texts: { [string]: string }?,
	effects: { [string]: Effect }?
): { string }
	local effectTable = effects or DEFAULT_EFFECTS
	local lines: { string } = {}
	for _, name in ORDER do
		local value = (events :: any)[name]
		if value ~= nil then
			local effect = effectTable[name] or DEFAULT_EFFECTS[name]
			table.insert(
				lines,
				Text.lookup(texts, effect.textKey, {
					count = value,
					coins = value,
					upgrade = value,
					zone = value,
				})
			)
		end
	end
	return lines
end

function FeedbackView.new(parent: Instance, effects: { [string]: Effect }?, lifetimeSeconds: number?): FeedbackView
	local lifetime = lifetimeSeconds or 1.5
	local gui = Instance.new("ScreenGui")
	gui.Name = "FactoryFeedback"
	gui.ResetOnSpawn = false
	local holder = Instance.new("Frame")
	holder.Name = "Popups"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.4)
	holder.Size = UDim2.fromOffset(400, 200)
	holder.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = holder
	gui.Parent = parent

	local view: FeedbackView = {
		show = function(_self, events: FeedbackModel.Events, texts: { [string]: string }?): { string }
			local lines = FeedbackView.messages(events, texts, effects)
			for index, line in lines do
				local popup = Instance.new("TextLabel")
				popup.BackgroundTransparency = 1
				popup.Size = UDim2.fromOffset(400, 40)
				popup.Font = Enum.Font.GothamBold
				popup.TextSize = 28
				popup.TextStrokeTransparency = 0.4
				popup.TextColor3 = Color3.fromRGB(255, 255, 255)
				popup.Text = line
				popup.LayoutOrder = index
				popup.Parent = holder
				task.delay(lifetime, function()
					popup:Destroy()
				end)
			end
			return lines
		end,
		destroy = function(_self)
			gui:Destroy()
		end,
	}
	return view
end

return FeedbackView
