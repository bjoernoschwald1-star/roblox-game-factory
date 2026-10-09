--!strict
-- Client des Probe-Raums von Game #002: rein lokale Bewegung der Optik, damit nichts im Takt repliziert wird.
-- Findet die Instanzen ueber das Attribut ProbeConfig.EFFECT_ATTRIBUTE:
--   flicker: Deckenleuchte setzt gelegentlich kurz aus (Licht, Neon-Leiste und sichtbarer Lichtkegel)
--   pulse:   rotes Notlicht pulsiert
--   sparks:  Funkenstoesse an der Konsole mit kurzem Lichtblitz
--   drone:   Drohne schwebt auf und ab und schwenkt (TweenService auf Zahlenwerte, keine Charakteranimation)
--   screen:  Konsolen-Bildschirm flackert leicht (Helligkeits-Tween der SurfaceGui, Licht folgt)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local ProbeConfig = require(ReplicatedStorage:WaitForChild("Game002Shared"):WaitForChild("ProbeConfig"))

local lights = ProbeConfig.lights
local effects = ProbeConfig.effects
local random = Random.new()
local started: { [Instance]: boolean } = {}

local function flicker(strip: BasePart)
	local light = strip:FindFirstChildWhichIsA("Light")
	local cone = strip:FindFirstChildWhichIsA("Beam")
	local onColor = strip.Color
	local offColor = onColor:Lerp(Color3.new(0, 0, 0), 0.85)
	local config = lights.ceiling
	local function set(on: boolean)
		if light ~= nil then
			light.Enabled = on
		end
		if cone ~= nil then
			cone.Enabled = on
		end
		strip.Color = if on then onColor else offColor
	end
	task.spawn(function()
		while strip.Parent ~= nil do
			task.wait(random:NextNumber(config.steadyMin, config.steadyMax))
			for _ = 1, random:NextInteger(1, config.dropouts) do
				set(false)
				task.wait(random:NextNumber(config.dropoutMin, config.dropoutMax))
				set(true)
				task.wait(random:NextNumber(config.dropoutMin, config.dropoutMax * 2))
			end
		end
	end)
end

local function pulse(lamp: BasePart)
	local light = lamp:FindFirstChildWhichIsA("PointLight")
	local onColor = lamp.Color
	local config = lights.emergency
	local connection
	connection = RunService.Heartbeat:Connect(function()
		if lamp.Parent == nil then
			connection:Disconnect()
			return
		end
		local wave = 0.5 + 0.5 * math.sin(os.clock() * 2 * math.pi / config.pulseSeconds)
		if light ~= nil then
			light.Brightness = config.brightness * (0.25 + 0.75 * wave)
		end
		lamp.Color = onColor:Lerp(Color3.new(0.15, 0, 0), 1 - wave)
	end)
end

local function sparks(part: BasePart)
	local emitter = part:FindFirstChildWhichIsA("ParticleEmitter")
	local flash = part:FindFirstChildWhichIsA("PointLight")
	if emitter == nil then
		return
	end
	task.spawn(function()
		while part.Parent ~= nil do
			task.wait(random:NextNumber(effects.sparkPauseMin, effects.sparkPauseMax))
			emitter:Emit(random:NextInteger(effects.sparkBurstMin, effects.sparkBurstMax))
			if flash ~= nil then
				flash.Brightness = 3
				TweenService:Create(flash, TweenInfo.new(0.25), { Brightness = 0 }):Play()
			end
		end
	end)
end

local function screen(panel: BasePart)
	local glow = panel:FindFirstChildWhichIsA("SurfaceLight")
	local gui = panel:FindFirstChildWhichIsA("SurfaceGui")
	local config = lights.screen
	local base = if glow ~= nil then glow.Brightness else 0
	local guiBase = if gui ~= nil then gui.Brightness else 0
	task.spawn(function()
		while panel.Parent ~= nil do
			task.wait(random:NextNumber(config.pauseMin, config.pauseMax))
			local dip = random:NextNumber(config.flickerMin, config.flickerMax)
			local info =
				TweenInfo.new(random:NextNumber(0.04, 0.12), Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, true)
			if gui ~= nil then
				TweenService:Create(gui, info, { Brightness = guiBase * (1 - dip) }):Play()
			end
			if glow ~= nil then
				TweenService:Create(glow, info, { Brightness = base * (1 - dip) }):Play()
			end
		end
	end)
end

local function drone(model: Model)
	local config = lights.drone
	local base = model:GetPivot()
	local bob = Instance.new("NumberValue")
	local sweep = Instance.new("NumberValue")
	sweep.Value = -config.sweepDegrees
	local function apply()
		model:PivotTo(base * CFrame.new(0, bob.Value, 0) * CFrame.Angles(0, math.rad(sweep.Value), 0))
	end
	bob.Changed:Connect(apply)
	sweep.Changed:Connect(apply)
	local bobInfo = TweenInfo.new(config.bobSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local sweepInfo = TweenInfo.new(config.sweepSeconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	TweenService:Create(bob, bobInfo, { Value = config.bobAmplitude }):Play()
	TweenService:Create(sweep, sweepInfo, { Value = config.sweepDegrees }):Play()
end

local function start(instance: Instance)
	local effect = instance:GetAttribute(ProbeConfig.EFFECT_ATTRIBUTE)
	if effect == nil or started[instance] then
		return
	end
	started[instance] = true
	if effect == "flicker" and instance:IsA("BasePart") then
		flicker(instance)
	elseif effect == "pulse" and instance:IsA("BasePart") then
		pulse(instance)
	elseif effect == "sparks" and instance:IsA("BasePart") then
		sparks(instance)
	elseif effect == "drone" and instance:IsA("Model") then
		drone(instance)
	elseif effect == "screen" and instance:IsA("BasePart") then
		screen(instance)
	end
end

local root = workspace:WaitForChild(ProbeConfig.FOLDER_NAME, 120)
if root ~= nil then
	-- Kinder koennen per Streaming nachkommen; erst nach dem Eintreffen (defer) starten, damit Licht und Emitter da sind
	root.DescendantAdded:Connect(function(instance)
		task.defer(start, instance)
	end)
	for _, instance in root:GetDescendants() do
		start(instance)
	end
end
