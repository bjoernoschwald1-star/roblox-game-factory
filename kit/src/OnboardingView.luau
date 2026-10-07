--!strict
-- Darstellung des Onboardings: Text-Hinweis oben in der Mitte und ein Beam vom Charakter zum Zielort.
-- Der Beam verbindet ein Attachment am Wurzelteil des Charakters mit einem Attachment in einem lokalen,
-- unsichtbaren Anker-Part am Ziel; ohne Ziel (target "none") oder ohne Charakter wird er ausgeblendet.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/Beam
--       https://create.roblox.com/docs/reference/engine/classes/Attachment
local OnboardingModel = require(script.Parent.OnboardingModel)
local Text = require(script.Parent.Text)

export type OnboardingView = {
	update: (
		self: OnboardingView,
		step: OnboardingModel.Step?,
		texts: { [string]: string }?,
		root: BasePart?,
		targetPosition: Vector3?
	) -> (),
	destroy: (self: OnboardingView) -> (),
}

local OnboardingView = {}

function OnboardingView.new(guiParent: Instance, worldParent: Instance, color: Color3?): OnboardingView
	local gui = Instance.new("ScreenGui")
	gui.Name = "FactoryOnboarding"
	gui.ResetOnSpawn = false
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.AnchorPoint = Vector2.new(0.5, 0)
	hint.Position = UDim2.new(0.5, 0, 0, 120)
	hint.Size = UDim2.fromOffset(520, 48)
	hint.BackgroundTransparency = 0.3
	hint.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
	hint.TextColor3 = Color3.fromRGB(255, 255, 255)
	hint.Font = Enum.Font.GothamBold
	hint.TextSize = 22
	hint.TextWrapped = true
	hint.Visible = false
	hint.Parent = gui
	gui.Parent = guiParent

	local anchor = Instance.new("Part")
	anchor.Name = "FactoryOnboardingTarget"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Parent = worldParent
	local targetAttachment = Instance.new("Attachment")
	targetAttachment.Parent = anchor
	local sourceAttachment = Instance.new("Attachment")
	sourceAttachment.Name = "FactoryOnboardingSource"
	local beam = Instance.new("Beam")
	beam.Attachment1 = targetAttachment
	beam.FaceCamera = true
	beam.Width0 = 0.6
	beam.Width1 = 0.6
	beam.Color = ColorSequence.new(color or Color3.fromRGB(255, 220, 90))
	beam.Enabled = false
	beam.Parent = anchor

	local view: OnboardingView = {
		update = function(
			_self,
			step: OnboardingModel.Step?,
			texts: { [string]: string }?,
			root: BasePart?,
			targetPosition: Vector3?
		)
			hint.Visible = step ~= nil
			hint.Text = if step ~= nil then Text.lookup(texts, step.textKey) else ""
			if step == nil or root == nil or targetPosition == nil then
				beam.Enabled = false
				return
			end
			if sourceAttachment.Parent ~= root then
				sourceAttachment.Parent = root
			end
			beam.Attachment0 = sourceAttachment
			anchor.Position = targetPosition + Vector3.new(0, 1, 0)
			beam.Enabled = true
		end,
		destroy = function(_self)
			gui:Destroy()
			anchor:Destroy()
			sourceAttachment:Destroy()
		end,
	}
	return view
end

return OnboardingView
