--!strict
-- Client-Start von Junkyard Magnet (LocalScript in StarterPlayerScripts): Zustand vom Server annehmen, Absichten
-- senden, Kit-Darstellung mit der Client-Config des Games starten. Keine Spielentscheidungen.
-- Requirt ausschliesslich die Client-Config (ReplicatedStorage.JunkyardShared.ClientConfig); Preise, Produkte,
-- Paesse und Rate Limits liegen nur in der Server-Config.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
-- Roblox-Werkzeugleiste ausblenden: der Magnet ist immer ausgeruestet, Bedienung ueber den runden Knopf.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/StarterGui#SetCoreGuiEnabled
game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
local playerGui = player:WaitForChild("PlayerGui")
local FactoryClient = ReplicatedStorage:WaitForChild("FactoryClient")
local FactoryKit = ReplicatedStorage:WaitForChild("FactoryKit")

local ClientState = require(FactoryClient:WaitForChild("ClientState"))
local Intents = require(FactoryClient:WaitForChild("Intents"))
local ItemView = require(FactoryKit:WaitForChild("ItemView"))
local CollectFx = require(FactoryKit:WaitForChild("CollectFx"))
local RangeView = require(FactoryKit:WaitForChild("RangeView"))
local HudModel = require(FactoryKit:WaitForChild("HudModel"))
local Locale = require(FactoryKit:WaitForChild("Locale"))
local AlbumModel = require(FactoryKit:WaitForChild("AlbumModel"))
local HudView = require(FactoryKit:WaitForChild("HudView"))
local FeedbackModel = require(FactoryKit:WaitForChild("FeedbackModel"))
local FeedbackView = require(FactoryKit:WaitForChild("FeedbackView"))
local OnboardingModel = require(FactoryKit:WaitForChild("OnboardingModel"))
local OnboardingView = require(FactoryKit:WaitForChild("OnboardingView"))
local InputModel = require(FactoryKit:WaitForChild("InputModel"))
local InputView = require(FactoryKit:WaitForChild("InputView"))
local ClientConfig = require(ReplicatedStorage:WaitForChild("JunkyardShared"):WaitForChild("ClientConfig"))

-- Sprache nach der Spieler-Locale (de-* -> Deutsch, sonst Englisch). Nur im lokalen Studio-Spieltest
-- (PlaceId 0) erzwingt das Workspace-Attribut StudioLocale (z. B. "en-us") eine Sprache fuer Pruefungen.
local studioLocale = if game.PlaceId == 0 then workspace:GetAttribute("StudioLocale") else nil
local localeId = if type(studioLocale) == "string" then studioLocale else Locale.localeOf(player)
local language = Locale.languageFor(localeId, ClientConfig.textsByLanguage, ClientConfig.defaultLanguage)
local texts = Locale.texts(ClientConfig.textsByLanguage, language, ClientConfig.defaultLanguage)

-- Schilder der Welt (vom Server in der Standardsprache, mit Attribut textKey) lokal in die Spielersprache setzen;
-- die Aenderung sieht nur dieser Spieler.
task.spawn(function()
	local world = workspace:WaitForChild("FactoryWorld", 30)
	if world == nil then
		return
	end
	local function localize(instance: Instance)
		local key = instance:GetAttribute("textKey")
		if instance:IsA("TextLabel") and type(key) == "string" and texts[key] ~= nil then
			instance.Text = texts[key]
		end
	end
	for _, descendant in world:GetDescendants() do
		localize(descendant)
	end
	world.DescendantAdded:Connect(localize)
end)
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

-- Album-Vorschau: die geladenen Item-Modelle (ReplicatedStorage.JunkyardModels, Asset-Schluessel = Album-Eintrag).
local hud = HudView.new(playerGui, intents, ClientConfig.uiTokens, {
	rarityColors = rarityColors,
	preview = function(entryId: string): Model?
		local models = ReplicatedStorage:FindFirstChild("JunkyardModels")
		local model = if models ~= nil then models:FindFirstChild(entryId) else nil
		return if model ~= nil and model:IsA("Model") then model else nil
	end,
})
local feedback = FeedbackView.new(playerGui, ClientConfig.effects, nil, {
	adornee = rootPart,
	camera = workspace.CurrentCamera,
	rarityColors = rarityColors,
})
local onboarding = OnboardingModel.new(ClientConfig.onboardingSteps)
local onboardingView = OnboardingView.new(playerGui, workspace, ClientConfig.uiTokens.highlight)
local collectFx = CollectFx.new(fxFolder, { clock = os.clock })
-- Reichweiten-Kreis: zeigt nach einem Reichweiten-Upgrade kurz, wie weit der Magnet jetzt zieht.
local rangeView = RangeView.new(fxFolder, ClientConfig.palette.gold)
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
	if shown.albumNew ~= nil then
		local entry = ClientConfig.album.entries[shown.albumNew]
		shown.albumNew = if entry then texts[entry.nameKey] or shown.albumNew else shown.albumNew
	end
	if shown.albumCompleted ~= nil then
		local nameKey = ClientConfig.album.groups[shown.albumCompleted]
		shown.albumCompleted = if nameKey then texts[nameKey] or shown.albumCompleted else shown.albumCompleted
	end
	return shown
end

local function reconcileItems(items: { ItemView.Item }, events: FeedbackModel.Events)
	ItemView.reconcile(itemFolder, items, ClientConfig.assetStyles, itemAssets, {
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
end

-- Geladene Modelle (Server: ReplicatedStorage.JunkyardModels, je Item-Asset ein Model) ersetzen die Bauteile;
-- vorhandene Items werden einmal neu aufgebaut. Fehlt eine Vorlage, bleibt die Bauteil-Version.
task.spawn(function()
	local models = ReplicatedStorage:WaitForChild("JunkyardModels", 60)
	if models == nil then
		return
	end
	local used = 0
	for asset, style in ClientConfig.assetStyles do
		local model = models:FindFirstChild(asset)
		if model ~= nil and model:IsA("Model") then
			(style :: any).model = model
			used += 1
		end
	end
	if used > 0 and latest ~= nil then
		itemFolder:ClearAllChildren()
		reconcileItems(latest.items, {})
	end
end)

state:onChanged(function(snapshot)
	local events = if latest ~= nil then FeedbackModel.compare(latest, snapshot, rarities) else {}
	reconcileItems(snapshot.items, events)
	hud:render(HudModel.build(snapshot, ClientConfig, texts))
	hud:renderAlbum(AlbumModel.build(snapshot, ClientConfig.album, texts))
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

-- Magnet-Werkzeug: Benutzen (Klick bzw. Tippen) sendet dieselbe Absicht wie E.
local function bindTool(tool: Instance)
	if tool:IsA("Tool") and tool.Name == "Magnet" and not tool:GetAttribute("bound") then
		tool:SetAttribute("bound", true)
		tool.Activated:Connect(function()
			intents:collect()
		end)
	end
end
player.CharacterAdded:Connect(function(character)
	character.ChildAdded:Connect(bindTool)
	player:WaitForChild("Backpack").ChildAdded:Connect(bindTool)
	for _, tool in player:WaitForChild("Backpack"):GetChildren() do
		bindTool(tool)
	end
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
	rangeView:update(rootPart(), if latest ~= nil then latest.range else nil, now)
	local root = rootPart()
	-- Volles Inventar: Hinweis und Strahl zur Verkaufsflaeche haben Vorrang vor dem Onboarding.
	local full = latest ~= nil and latest.inventoryCount >= latest.capacity
	-- Waehrend eines Wow-Banners (gleicher Platz) ist der Hinweis ausgeblendet.
	local step = OnboardingModel.displayStep(feedback:banner() ~= nil, full, onboarding:current())
	onboardingView:update(step, texts, root, targetPosition(step, root))
end)
