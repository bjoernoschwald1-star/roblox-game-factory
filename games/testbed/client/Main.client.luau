--!strict
-- Client-Start des Testbeds (LocalScript in StarterPlayerScripts): Zustand vom Server annehmen, Absichten
-- senden, Kit-Darstellung mit der Client-Config des Games starten. Keine Spielentscheidungen.
-- Requirt ausschliesslich die Client-Config (ReplicatedStorage.TestbedShared.ClientConfig); Preise, Produkte,
-- Paesse und Rate Limits liegen nur in der Server-Config.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local FactoryClient = ReplicatedStorage:WaitForChild("FactoryClient")
local FactoryKit = ReplicatedStorage:WaitForChild("FactoryKit")

local ClientState = require(FactoryClient:WaitForChild("ClientState"))
local Intents = require(FactoryClient:WaitForChild("Intents"))
local ItemView = require(FactoryKit:WaitForChild("ItemView"))
local CollectFx = require(FactoryKit:WaitForChild("CollectFx"))
local HudModel = require(FactoryKit:WaitForChild("HudModel"))
local HudView = require(FactoryKit:WaitForChild("HudView"))
local FeedbackModel = require(FactoryKit:WaitForChild("FeedbackModel"))
local FeedbackView = require(FactoryKit:WaitForChild("FeedbackView"))
local OnboardingModel = require(FactoryKit:WaitForChild("OnboardingModel"))
local OnboardingView = require(FactoryKit:WaitForChild("OnboardingView"))
local InputModel = require(FactoryKit:WaitForChild("InputModel"))
local InputView = require(FactoryKit:WaitForChild("InputView"))
local ClientConfig = require(ReplicatedStorage:WaitForChild("TestbedShared"):WaitForChild("ClientConfig"))

local texts = ClientConfig.texts
local itemAssets: { [string]: string } = {}
local rarities: { [string]: string } = {}
for itemTypeId, item in ClientConfig.items do
	itemAssets[itemTypeId] = item.asset
	rarities[itemTypeId] = item.rarity
end
local rarityColors: { [string]: Color3 } = {}
for rarity, style in ClientConfig.rarityStyles do
	if (style :: any).accent ~= nil then
		rarityColors[rarity] = (style :: any).accent
	end
end

local remotes = ReplicatedStorage:WaitForChild("FactoryRemotes")
local intents = Intents.fromRemotes(remotes)
local state = ClientState.new()

local itemFolder = Instance.new("Folder")
itemFolder.Name = "FactoryLocalItems"
itemFolder.Parent = workspace
local fxFolder = Instance.new("Folder")
fxFolder.Name = "FactoryCollectFx"
fxFolder.Parent = workspace

local function rootPart(): BasePart?
	local character = player.Character
	if character == nil then
		return nil
	end
	local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
	return if root ~= nil and root:IsA("BasePart") then root else nil
end

local hud = HudView.new(playerGui, intents, ClientConfig.uiTokens)
local feedback = FeedbackView.new(playerGui, ClientConfig.effects, nil, {
	adornee = rootPart,
	camera = workspace.CurrentCamera,
	rarityColors = rarityColors,
})
local onboarding = OnboardingModel.new(ClientConfig.onboardingSteps)
local onboardingView = OnboardingView.new(playerGui, workspace, ClientConfig.uiTokens.highlight)
local collectFx = CollectFx.new(fxFolder, { clock = os.clock })
local latest: any = nil

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
		local upgrade = ClientConfig.upgrades[shown.upgraded]
		shown.upgraded = if upgrade then texts[upgrade.nameKey] or shown.upgraded else shown.upgraded
	end
	if shown.unlocked ~= nil then
		local zone = ClientConfig.zones[shown.unlocked]
		shown.unlocked = if zone then texts[zone.nameKey] or shown.unlocked else shown.unlocked
	end
	if shown.found ~= nil then
		local item = ClientConfig.items[shown.found]
		shown.found = if item then texts[item.nameKey] or shown.found else shown.found
	end
	return shown
end

state:onChanged(function(snapshot)
	local events = if latest ~= nil then FeedbackModel.compare(latest, snapshot, rarities) else {}
	ItemView.reconcile(itemFolder, snapshot.items, ClientConfig.assetStyles, itemAssets, {
		rarities = rarities,
		rarityStyles = ClientConfig.rarityStyles,
		-- Eingesammelte Items fliegen zum Charakter statt zu verschwinden.
		onRemove = function(part: BasePart): boolean
			if events.collected == nil then
				return false
			end
			local rarity = part:GetAttribute("rarity")
			local color = if type(rarity) == "string" then rarityColors[rarity] else nil
			return collectFx:pull(part, rootPart(), color)
		end,
	})
	hud:render(HudModel.build(snapshot, ClientConfig))
	if latest ~= nil then
		feedback:show(displayEvents(events), texts)
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

RunService.Heartbeat:Connect(function()
	local now = os.clock()
	ItemView.animate(itemFolder, now)
	collectFx:update(now)
	local root = rootPart()
	-- Volles Inventar: Hinweis und Strahl zur Verkaufsflaeche haben Vorrang vor dem Onboarding.
	local full = latest ~= nil and latest.inventoryCount >= latest.capacity
	-- Waehrend eines Wow-Banners (gleicher Platz) ist der Hinweis ausgeblendet.
	local step = OnboardingModel.displayStep(feedback:banner() ~= nil, full, onboarding:current())
	onboardingView:update(step, texts, root, targetPosition(step, root))
end)
