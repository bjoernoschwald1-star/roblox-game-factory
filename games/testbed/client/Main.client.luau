--!strict
-- Client-Start des Testbeds (LocalScript in StarterPlayerScripts): Zustand vom Server annehmen, Absichten
-- senden, Kit-Darstellung mit Texten, assetStyles und uiTokens des Games starten. Keine Spielentscheidungen.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local FactoryClient = ReplicatedStorage:WaitForChild("FactoryClient")
local FactoryKit = ReplicatedStorage:WaitForChild("FactoryKit")

local ClientState = require(FactoryClient:WaitForChild("ClientState"))
local Intents = require(FactoryClient:WaitForChild("Intents"))
local ItemView = require(FactoryKit:WaitForChild("ItemView"))
local HudModel = require(FactoryKit:WaitForChild("HudModel"))
local HudView = require(FactoryKit:WaitForChild("HudView"))
local FeedbackModel = require(FactoryKit:WaitForChild("FeedbackModel"))
local FeedbackView = require(FactoryKit:WaitForChild("FeedbackView"))
local OnboardingModel = require(FactoryKit:WaitForChild("OnboardingModel"))
local OnboardingView = require(FactoryKit:WaitForChild("OnboardingView"))
local InputModel = require(FactoryKit:WaitForChild("InputModel"))
local InputView = require(FactoryKit:WaitForChild("InputView"))
local Testbed = require(ReplicatedStorage:WaitForChild("TestbedShared"):WaitForChild("Config"))

local config = Testbed.config
local texts = config.texts
local itemAssets: { [string]: string } = {}
for itemTypeId, item in config.items do
	itemAssets[itemTypeId] = item.asset
end

local remotes = ReplicatedStorage:WaitForChild("FactoryRemotes")
local intents = Intents.fromRemotes(remotes)
local state = ClientState.new()

local itemFolder = Instance.new("Folder")
itemFolder.Name = "FactoryLocalItems"
itemFolder.Parent = workspace

local hud = HudView.new(playerGui, intents, Testbed.uiTokens)
local feedback = FeedbackView.new(playerGui)
local onboarding = OnboardingModel.new(Testbed.onboardingSteps)
local onboardingView = OnboardingView.new(playerGui, workspace)
local latest: any = nil

local function rootPart(): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

-- Zielort des Onboardings: naechstes eigenes Item bzw. die Verkaufsflaeche.
local function targetPosition(step: OnboardingModel.Step?, root: BasePart?): Vector3?
	if step == nil or latest == nil then
		return nil
	end
	if step.target == "item" and root ~= nil then
		local best: Vector3? = nil
		local bestDistance = math.huge
		for _, item in latest.items do
			local distance = (item.position - root.Position).Magnitude
			if distance < bestDistance then
				best, bestDistance = item.position, distance
			end
		end
		return best
	elseif step.target == "sell" then
		local world = workspace:FindFirstChild("FactoryWorld")
		local sellAreas = world and world:FindFirstChild("SellAreas")
		local area = sellAreas and sellAreas:FindFirstChildWhichIsA("BasePart")
		return if area ~= nil then (area :: BasePart).Position else nil
	end
	return nil
end

-- Ereignis-IDs fuer die Popups in Anzeigenamen uebersetzen.
local function displayEvents(events: FeedbackModel.Events): FeedbackModel.Events
	local shown = table.clone(events)
	if shown.upgraded ~= nil then
		local upgrade = config.upgrades[shown.upgraded]
		shown.upgraded = if upgrade then texts[upgrade.nameKey] or shown.upgraded else shown.upgraded
	end
	if shown.unlocked ~= nil then
		local zone = config.zones[shown.unlocked]
		shown.unlocked = if zone then texts[zone.nameKey] or shown.unlocked else shown.unlocked
	end
	return shown
end

state:onChanged(function(snapshot)
	ItemView.reconcile(itemFolder, snapshot.items, Testbed.assetStyles, itemAssets)
	hud:render(HudModel.build(snapshot, config))
	if latest ~= nil then
		feedback:show(displayEvents(FeedbackModel.compare(latest, snapshot)), texts)
	end
	latest = snapshot
	onboarding:update(snapshot)
end)

local stateUpdate = remotes:WaitForChild("stateUpdate") :: RemoteEvent
stateUpdate.OnClientEvent:Connect(function(snapshot)
	state:apply(snapshot)
end)

InputView.new(InputModel.new({ intents = intents }), function()
	return latest
end, function(): Vector3?
	local root = rootPart()
	return if root ~= nil then root.Position else nil
end)

game:GetService("RunService").Heartbeat:Connect(function()
	local root = rootPart()
	local step = onboarding:current()
	onboardingView:update(step, texts, root, targetPosition(step, root))
end)
