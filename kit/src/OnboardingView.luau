--!strict
-- Darstellung des Onboardings: Text-Hinweis unter der obersten HUD-Zeile und ein Beam vom Charakter zum Zielort.
-- Der Hinweis nutzt die Vorlage "hint" aus HudLayout (hoechstens 90 % der Breite, Skalenwerte), Text skaliert und
-- bricht um (TextScaled + UITextSizeConstraint) statt abgeschnitten zu werden; bei Groessenaenderung neu angeordnet.
-- Der Beam verbindet ein Attachment am Wurzelteil des Charakters mit einem Attachment in einem lokalen,
-- unsichtbaren Anker-Part am Ziel; ohne Ziel (target "none") oder ohne Charakter wird er ausgeblendet.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/Beam
--       https://create.roblox.com/docs/reference/engine/classes/Attachment
local HudLayout = require(script.Parent.HudLayout)
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
	hint: (self: OnboardingView) -> TextLabel,
	beam: (self: OnboardingView) -> Beam,
	destroy: (self: OnboardingView) -> (),
}

local OnboardingView = {}

-- Der Hinweis ist klein und oben (HudLayout "hint"); er erscheint bei jedem neuen Text und verschwindet nach
-- HINT_SECONDS wieder (der Strahl bleibt). clock ist injizierbar (Test).
local HINT_SECONDS = 6

OnboardingView.HINT_SECONDS = HINT_SECONDS

function OnboardingView.new(
	guiParent: Instance,
	worldParent: Instance,
	color: Color3?,
	clock: (() -> number)?
): OnboardingView
	local now = clock or os.clock
	local shownText: string? = nil
	local shownAt = 0
	local gui = Instance.new("ScreenGui")
	gui.Name = "FactoryOnboarding"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	local hint = Instance.new("TextLabel")
	hint.Name = "Hint"
	hint.BackgroundTransparency = 0.25
	hint.BackgroundColor3 = Color3.fromRGB(20, 20, 30)
	hint.BorderSizePixel = 0
	hint.TextColor3 = Color3.fromRGB(255, 255, 255)
	hint.Font = Enum.Font.GothamBold
	hint.TextScaled = true
	hint.Visible = false
	local sizeLimit = Instance.new("UITextSizeConstraint")
	sizeLimit.MaxTextSize = 18
	sizeLimit.MinTextSize = 10
	sizeLimit.Parent = hint
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = hint
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0.03, 0)
	padding.PaddingRight = UDim.new(0.03, 0)
	padding.Parent = hint
	hint.Parent = gui
	local function layout()
		local area = gui.AbsoluteSize
		HudLayout.apply(hint, HudLayout.specs(HudLayout.presetFor(area), 0, area).hint)
	end
	layout()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
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
			local text = if step ~= nil then Text.lookup(texts, step.textKey) else ""
			if text ~= shownText then
				shownText = text
				shownAt = now()
			end
			hint.Text = text
			hint.Visible = step ~= nil and now() - shownAt < HINT_SECONDS
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
		hint = function(_self): TextLabel
			return hint
		end,
		beam = function(_self): Beam
			return beam
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
