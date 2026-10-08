--!strict
-- Darstellung des Feedbacks ohne Assets.
-- Popups: kurze Texte (z. B. "+12") als BillboardGui am Charakter (options.adornee liefert das Wurzelteil); ohne
-- Charakter erscheinen sie ersatzweise in der Bildschirmmitte. Groesse waechst mit der Seltenheit des Fundes.
-- Wow-Moment: Fund ab epic (FeedbackModel.wowLevel) zeigt ein Banner mit Seltenheitsname und Itemname in der
-- Seltenheitsfarbe; legendary zusaetzlich ein kurzer, heller Bildschirm-Schimmer. Kamerawirkung nur als sanfter
-- Sichtfeld-Impuls (epic +3, legendary +6 Grad, 0,35 s hin und zurueck), kein Wackeln (Uebelkeitsrisiko). Das
-- Basis-Sichtfeld wird beim Erzeugen gemerkt; waehrend eines Impulses startet kein zweiter (kein Aufsummieren).
-- Das Banner nimmt den Platz des Onboarding-Hinweises ein (HudLayout-Vorlage "hint"); der Client blendet den
-- Hinweis aus, solange banner() ein Banner liefert - so ueberdeckt es kein HUD-Element.
-- Effekt-Tabelle des Games: je Ereignis { textKey, color }; fehlt ein Eintrag, gilt DEFAULT_EFFECTS.
-- effects.sounds[ereignis] = SoundId des Games; das Kit spielt nur, wenn das Game eine ID liefert.
-- Upgrade gekauft: kurzer, wachsender Lichtball ("UpgradeBurst") am Charakter in der Upgrade-Farbe.
-- Popups verschwinden nach lifetimeSeconds (options.schedule ersetzt task.delay, z. B. im Test).
-- Doku: https://create.roblox.com/docs/reference/engine/classes/BillboardGui
--       https://create.roblox.com/docs/reference/engine/classes/Camera#FieldOfView
--       https://create.roblox.com/docs/reference/engine/classes/Sound
local FeedbackModel = require(script.Parent.FeedbackModel)
local HudLayout = require(script.Parent.HudLayout)
local Text = require(script.Parent.Text)

export type Effect = {
	textKey: string,
	color: Color3?,
}

export type Options = {
	adornee: (() -> BasePart?)?,
	camera: Camera?,
	schedule: ((seconds: number, callback: () -> ()) -> ())?,
	rarityColors: { [string]: Color3 }?,
	worldParent: Instance?, -- fuer den Upgrade-Effekt am Charakter (Standard workspace)
}

export type FeedbackView = {
	show: (self: FeedbackView, events: FeedbackModel.Events, texts: { [string]: string }?) -> { string },
	banner: (self: FeedbackView) -> TextLabel?,
	destroy: (self: FeedbackView) -> (),
}

local DEFAULT_EFFECTS: { [string]: Effect } = {
	collected = { textKey = "feedback_collected", color = Color3.fromRGB(255, 255, 255) },
	earned = { textKey = "feedback_earned", color = Color3.fromRGB(255, 220, 90) },
	upgraded = { textKey = "feedback_upgraded", color = Color3.fromRGB(120, 220, 255) },
	unlocked = { textKey = "feedback_unlocked", color = Color3.fromRGB(140, 255, 140) },
	full = { textKey = "feedback_full", color = Color3.fromRGB(255, 120, 120) },
	found = { textKey = "feedback_found", color = Color3.fromRGB(200, 110, 255) },
	prestiged = { textKey = "feedback_prestiged", color = Color3.fromRGB(255, 150, 40) },
}
local ORDER = { "collected", "earned", "upgraded", "unlocked", "full" }
local POPUP_SCALE = { 1, 1.2, 1.45, 1.8 } -- nach FeedbackModel.rank
local FOV_PUNCH = { 3, 6 } -- nach FeedbackModel.wowLevel

local FeedbackView = {}

FeedbackView.DEFAULT_EFFECTS = DEFAULT_EFFECTS
FeedbackView.POPUP_SCALE = POPUP_SCALE

local function effectFor(effects: { [string]: any }?, name: string): Effect
	local custom = if effects ~= nil then effects[name] else nil
	return if type(custom) == "table" and type(custom.textKey) == "string" then custom else DEFAULT_EFFECTS[name]
end

-- Liefert die Popup-Texte zu den Ereignissen in fester Reihenfolge (reine Logik, auch fuer Tests).
function FeedbackView.messages(
	events: FeedbackModel.Events,
	texts: { [string]: string }?,
	effects: { [string]: any }?
): { string }
	local lines: { string } = {}
	for _, name in ORDER do
		local value = (events :: any)[name]
		if value ~= nil then
			table.insert(
				lines,
				Text.lookup(texts, effectFor(effects, name).textKey, {
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

-- Banner-Text eines Fundes ab epic, sonst nil. events.found ist hier bereits der Anzeigename des Items.
function FeedbackView.bannerText(
	events: FeedbackModel.Events,
	texts: { [string]: string }?,
	effects: { [string]: any }?
): string?
	if events.found == nil or not FeedbackModel.isWow(events.foundRarity) then
		return nil
	end
	local rarityName = Text.lookup(texts, "rarity_" .. tostring(events.foundRarity))
	return Text.lookup(texts, effectFor(effects, "found").textKey, { rarity = rarityName, item = events.found })
end

function FeedbackView.new(
	parent: Instance,
	effects: { [string]: any }?,
	lifetimeSeconds: number?,
	options: Options?
): FeedbackView
	local opts: Options = options or {}
	local lifetime = lifetimeSeconds or 1.5
	local schedule = opts.schedule or function(seconds: number, callback: () -> ())
		task.delay(seconds, callback)
	end
	local TweenService = game:GetService("TweenService")

	local gui = Instance.new("ScreenGui")
	gui.Name = "FactoryFeedback"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	local holder = Instance.new("Frame")
	holder.Name = "Popups"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.45)
	holder.Size = UDim2.fromScale(0.8, 0.2)
	holder.Parent = gui
	local layout = Instance.new("UIListLayout")
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = holder
	-- Billboards liegen in einem eigenen Ordner neben dem ScreenGui (PlayerGui bzw. Test-Container).
	local billboards = Instance.new("Folder")
	billboards.Name = "FactoryFeedbackBillboards"
	billboards.Parent = parent
	gui.Parent = parent

	local currentBanner: TextLabel? = nil
	local fovBase: number? = if opts.camera ~= nil then opts.camera.FieldOfView else nil
	local punching = false

	local function playSound(name: string)
		local sounds = if effects ~= nil then effects.sounds else nil
		local soundId = if type(sounds) == "table" then sounds[name] else nil
		if type(soundId) ~= "string" or soundId == "" then
			return
		end
		local sound = Instance.new("Sound")
		sound.SoundId = soundId
		sound.Parent = gui
		sound:Play()
		sound.Ended:Once(function()
			sound:Destroy()
		end)
	end

	local function popup(line: string, color: Color3, scale: number, index: number)
		local root = if opts.adornee ~= nil then opts.adornee() else nil
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextScaled = true
		label.TextStrokeTransparency = 0.2
		label.TextColor3 = color
		label.Text = line
		label.Size = UDim2.fromScale(1, 1)
		if root ~= nil then
			local billboard = Instance.new("BillboardGui")
			billboard.Name = "Popup"
			billboard.Adornee = root
			billboard.AlwaysOnTop = true
			billboard.LightInfluence = 0
			billboard.Size = UDim2.fromOffset(math.floor(200 * scale), math.floor(44 * scale))
			-- Gestaffelt nach noch sichtbaren Popups, damit schnelle Folgen nicht uebereinander liegen.
			local stack = (#billboards:GetChildren() + index - 1) % 4
			billboard.StudsOffset = Vector3.new(0, 3 + stack * 1.4, 0)
			label.Parent = billboard
			billboard.Parent = billboards
			TweenService:Create(billboard, TweenInfo.new(lifetime), {
				StudsOffset = billboard.StudsOffset + Vector3.new(0, 2, 0),
			}):Play()
			schedule(lifetime, function()
				billboard:Destroy()
			end)
		else
			label.Name = "Popup"
			label.Size = UDim2.new(1, 0, 0, math.floor(36 * scale))
			label.LayoutOrder = index
			label.Parent = holder
			schedule(lifetime, function()
				label:Destroy()
			end)
		end
	end

	local function upgradeBurst(color: Color3)
		local root = if opts.adornee ~= nil then opts.adornee() else nil
		if root == nil then
			return
		end
		local burst = Instance.new("Part")
		burst.Name = "UpgradeBurst"
		burst.Shape = Enum.PartType.Ball
		burst.Anchored = true
		burst.CanCollide = false
		burst.CanQuery = false
		burst.CanTouch = false
		burst.Material = Enum.Material.Neon
		burst.Color = color
		burst.Transparency = 0.35
		burst.Size = Vector3.one * 2
		burst.Position = root.Position
		burst.Parent = opts.worldParent or workspace
		TweenService:Create(burst, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * 10,
			Transparency = 1,
		}):Play()
		schedule(0.6, function()
			burst:Destroy()
		end)
	end

	-- Grosses Banner auf dem Platz des Hinweises; level 2 zusaetzlich mit Bildschirm-Blitz. sound = Effektname.
	local function celebrate(text: string, color: Color3, level: number, sound: string)
		if currentBanner ~= nil then
			currentBanner:Destroy()
		end
		local banner = Instance.new("TextLabel")
		banner.Name = "WowBanner"
		HudLayout.apply(banner, HudLayout.specs(HudLayout.presetFor(gui.AbsoluteSize), 0, gui.AbsoluteSize).hint)
		banner.BackgroundTransparency = 1
		banner.Font = Enum.Font.GothamBlack
		banner.TextScaled = true
		banner.TextColor3 = color
		banner.TextStrokeTransparency = 0
		banner.Text = text
		local sizeLimit = Instance.new("UITextSizeConstraint")
		sizeLimit.MaxTextSize = if level >= 2 then 64 else 48
		sizeLimit.MinTextSize = 18
		sizeLimit.Parent = banner
		local pop = Instance.new("UIScale")
		pop.Scale = 0.6
		pop.Parent = banner
		banner.Parent = gui
		currentBanner = banner
		TweenService:Create(pop, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		schedule(lifetime + 0.6 * level, function()
			if currentBanner == banner then
				currentBanner = nil
			end
			banner:Destroy()
		end)
		if level >= 2 then
			local flash = Instance.new("Frame")
			flash.Name = "WowFlash"
			flash.Size = UDim2.fromScale(1, 1)
			flash.BackgroundColor3 = color
			flash.BackgroundTransparency = 0.6
			flash.BorderSizePixel = 0
			flash.ZIndex = 0
			flash.Parent = gui
			TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
			schedule(0.6, function()
				flash:Destroy()
			end)
		end
		local camera = opts.camera
		if camera ~= nil and fovBase ~= nil and level > 0 and not punching then
			punching = true
			local base = fovBase :: number
			TweenService:Create(
				camera,
				TweenInfo.new(0.175, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0, true),
				{ FieldOfView = math.clamp(base + FOV_PUNCH[level], 1, 120) }
			):Play()
			schedule(0.4, function()
				camera.FieldOfView = base
				punching = false
			end)
		end
		playSound(sound)
	end

	local function wow(text: string, rarity: string?)
		local colors = opts.rarityColors or {}
		local color = colors[rarity or ""] or effectFor(effects, "found").color or Color3.fromRGB(255, 255, 255)
		celebrate(text, color, FeedbackModel.wowLevel(rarity), "found")
	end

	local view: FeedbackView = {
		show = function(_self, events: FeedbackModel.Events, texts: { [string]: string }?): { string }
			local lines = FeedbackView.messages(events, texts, effects)
			local index = 0
			for _, name in ORDER do
				if (events :: any)[name] ~= nil then
					index += 1
					local scale = if name == "collected" then POPUP_SCALE[FeedbackModel.rank(events.foundRarity)] else 1
					popup(lines[index], effectFor(effects, name).color or Color3.new(1, 1, 1), scale, index)
					playSound(name)
					if name == "upgraded" then
						upgradeBurst(effectFor(effects, name).color or Color3.fromRGB(120, 220, 255))
					end
				end
			end
			if events.prestiged ~= nil then
				local effect = effectFor(effects, "prestiged")
				local color = effect.color or Color3.fromRGB(255, 150, 40)
				local multiplier = Text.decimal(events.prestigeMultiplier or 1, texts)
				celebrate(Text.lookup(texts, effect.textKey, { multiplier = multiplier }), color, 2, "prestiged")
				upgradeBurst(color)
				return lines
			end
			local text = FeedbackView.bannerText(events, texts, effects)
			if text ~= nil then
				wow(text, events.foundRarity)
			end
			return lines
		end,
		banner = function(_self): TextLabel?
			return currentBanner
		end,
		destroy = function(_self)
			gui:Destroy()
			billboards:Destroy()
		end,
	}
	return view
end

return FeedbackView
