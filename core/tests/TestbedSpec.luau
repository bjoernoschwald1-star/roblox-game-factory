--!strict
-- Tests 111-113, 116: Testbed-Game (Config, Welt-Aufbau, Server-Start ohne echte Spieler, Grenzen der
-- Client-Config). Die Start-Skripte selbst laufen hier nicht (LocalScripts gibt es in Luau Execution nicht; das
-- Server-Skript liegt nicht im CI-Build). World und ServerConfig kommen aus dem CI-Testeintrag
-- ServerScriptService.TestbedServerUnderTest (nur ModuleScripts).
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local Validator = require(FactoryCore.server.Config.Validator)
local Simulator = require(FactoryCore.server.Config.Simulator)
local ServerRuntime = require(FactoryCore.server.Engine.ServerRuntime)
local WorldAdapter = require(FactoryCore.server.Engine.WorldAdapter)
local PlayersAdapter = require(FactoryCore.server.Engine.PlayersAdapter)
local Scheduler = require(FactoryCore.server.Engine.Scheduler)
local Log = require(FactoryCore.shared.Log)
local OnboardingModel = require(ReplicatedStorage.FactoryKit.OnboardingModel)
local ClientConfig = require(ReplicatedStorage.TestbedShared.ClientConfig)
local ServerConfig = require(ServerScriptService.TestbedServerUnderTest.ServerConfig)
local World = require(ServerScriptService.TestbedServerUnderTest.World)

local config: any = ServerConfig
local SERVER_ONLY_KEYS = { "products", "passes", "remotes", "sim", "productId", "passId", "price", "spawnWeight" }

-- Sammelt alle Schluessel einer Tabelle rekursiv (Pfad -> Schluessel).
local function allKeys(value: any, path: string, found: { string })
	if type(value) ~= "table" then
		return
	end
	for key, child in value do
		local here = path .. "." .. tostring(key)
		table.insert(found, here)
		allKeys(child, here, found)
	end
end

local HUD_KEYS = {
	"hud_coins",
	"hud_inventory",
	"hud_full",
	"hud_level",
	"hud_cost",
	"hud_max",
	"hud_zone_purchase",
	"hud_zone_level",
	"hud_zone_coins",
	"hud_zone_all",
	"hud_unlock",
	"hud_collect",
	"hud_sell",
	"feedback_collected",
	"feedback_earned",
	"feedback_upgraded",
	"feedback_unlocked",
	"feedback_full",
	"feedback_found",
	"hint_full",
	"rarity_common",
	"rarity_rare",
	"rarity_epic",
	"rarity_legendary",
	"leaderstats_coins",
	"leaderstats_zone",
	"sign_sell",
	"system_load_failed",
}

-- Baut die Welt in einem temporaeren Ordner, fuehrt body aus und raeumt in jedem Fall auf.
local function withWorld(body: (container: Instance, root: Instance) -> ())
	local container = Instance.new("Folder")
	container.Name = "TestbedWorldTest"
	container.Parent = workspace
	local ok, err = pcall(function()
		body(container, World.build(config, container))
	end)
	container:Destroy()
	if not ok then
		error(err, 0)
	end
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("testbed", function()
		t.it("111 testbed config: valid, simulator reaches all zones, styles and texts complete", function()
			local result = Validator.validate(config)
			t.expect(Validator.format(result)).toBe("")
			t.expect(result.ok).toBe(true)

			local report = Simulator.run(config, { maxMinutes = 120, buyPolicy = "cheapest_first" })
			t.expect(report.reachedAllZones).toBe(true)
			print(
				string.format(
					"[spike] SIM testbed firstSell=%s firstUpgrade=%s zone2=%s zone3=%s coinsAtEnd=%d",
					tostring(report.minutesToFirstSell),
					tostring(report.minutesToFirstUpgrade),
					tostring(report.minutesToZone[2]),
					tostring(report.minutesToZone[3]),
					report.coinsAtEnd
				)
			)

			for itemId, item in config.items do
				t.expect({ itemId, ClientConfig.assetStyles[item.asset] ~= nil }).toEqual({ itemId, true })
			end
			-- Seltene Stufen: je Zone kleineres Gewicht und hoeherer Preis als jede gewoehnliche Stufe der Zone.
			local rarityCount: { [string]: number } = {}
			for itemId, item in config.items do
				local rarity = item.rarity or "common"
				rarityCount[rarity] = (rarityCount[rarity] or 0) + 1
				if rarity ~= "common" then
					for otherId, other in config.items do
						if other.zoneId == item.zoneId and (other.rarity or "common") == "common" then
							t.expect({ itemId, otherId, item.spawnWeight < other.spawnWeight, item.price > other.price })
								.toEqual({ itemId, otherId, true, true })
						end
					end
				end
			end
			t.expect(rarityCount).toEqual({ common = 4, rare = 3, epic = 3, legendary = 3 })
			local keys = table.clone(HUD_KEYS)
			for _, step in OnboardingModel.DEFAULT_STEPS do
				table.insert(keys, step.textKey)
			end
			for _, section in { config.items, config.zones, config.upgrades } do
				for _, entry in section do
					table.insert(keys, entry.nameKey)
				end
			end
			for _, key in keys do
				t.expect({ key, type(config.texts[key]) }).toEqual({ key, "string" })
			end
		end)

		t.it("112 World.build: zone parts, sell area, no unions; WorldAdapter finds nothing missing", function()
			withWorld(function(container: Instance, root: Instance)
				t.expect(root.Name).toBe("FactoryWorld")
				local zones = root:FindFirstChild("Zones") :: Instance
				for zoneId in config.zones do
					local zonePart = zones:FindFirstChild(zoneId)
					t.expect({ zoneId, zonePart ~= nil and zonePart:IsA("BasePart") }).toEqual({ zoneId, true })
				end
				t.expect(#(root:FindFirstChild("SellAreas") :: Instance):GetChildren() >= 1).toBe(true)
				for _, descendant in root:GetDescendants() do
					t.expect({ descendant.Name, descendant:IsA("PartOperation") }).toEqual({ descendant.Name, false })
					if descendant:IsA("BasePart") then
						t.expect({ descendant.Name, descendant.Anchored }).toEqual({ descendant.Name, true })
					end
				end
				t.expect(WorldAdapter.new(container):validateWorld(config)).toEqual({})
				t.expect(World.build(config, container)).toBe(root)
			end)
			t.expect(workspace:FindFirstChild("TestbedWorldTest")).toBe(nil)
		end)

		t.it(
			"113 testbed server without real players: starts, fake player collects via dispatch, state goes out",
			function()
				withWorld(function(container: Instance, root: Instance)
					local zoneA = (root:FindFirstChild("Zones") :: Instance):FindFirstChild("zone_a") :: BasePart
					local fired: { any } = {}
					local added: { (player: any) -> () } = {}
					local scheduler = Scheduler.fake()
					local characterPosition: Vector3? = nil
					local connection = { Disconnect = function() end }
					local signal = {
						Connect = function()
							return connection
						end,
					}
					local runtime = ServerRuntime.start(
						config,
						{
							adapters = {
								players = {
									onAdded = function(_self, callback)
										table.insert(added, callback)
										return connection
									end,
									onRemoving = function()
										return connection
									end,
									getPlayers = function()
										return {}
									end,
									kick = function() end,
									joinSource = function(_self, player)
										return PlayersAdapter.joinSourceOf(player)
									end,
								},
								character = {
									position = function(): Vector3?
										return characterPosition
									end,
								},
								remotes = {
									bind = function()
										return connection
									end,
									fireClient = function(_self, name: string, player: any, payload: any)
										table.insert(fired, { name = name, player = player, payload = payload })
									end,
								},
								world = WorldAdapter.new(container),
								market = {
									setReceiptHandler = function() end,
									ownsPass = function()
										return false
									end,
									onPassPromptFinished = function()
										return signal:Connect()
									end,
									onProductPromptFinished = function()
										return signal:Connect()
									end,
									clearReceiptHandler = function() end,
								},
								analytics = { sink = function() end },
								scheduler = scheduler,
								lifecycle = { bindToClose = function() end },
							},
							storage = MemoryAdapter.new(),
							keyPrefix = "testbed_",
							serverId = "server-test",
							clock = function()
								return 1000
							end,
							sleep = function() end,
							rng = Random.new(71),
							log = Log.new({ sink = function() end }),
						} :: any
					)

					local player = {
						UserId = 101,
						GetJoinData = function()
							return { LaunchData = "organic" }
						end,
					}
					for _, callback in added do
						callback(player)
					end
					local ctx = { userId = 101 }
					local items = runtime.game.modules.collecting:instances(ctx) :: { any }
					t.expect(#items).toBe(10)
					for _, instance in items do
						local localPoint = zoneA.CFrame:PointToObjectSpace(instance.position)
						t.expect(math.abs(localPoint.Y - zoneA.Size.Y / 2) < 0.001).toBe(true)
					end

					-- Charakter steht neben dem ersten Item (Wurzelteil etwa 3 Studs ueber der Plattform).
					characterPosition = items[1].position + Vector3.new(0, 3, 0)
					t.expect({ runtime.game:dispatch(ctx, "collect") }).toEqual({ true })
					local collected = runtime.game.modules.inventory:count(ctx) :: number
					t.expect(collected > 0).toBe(true)
					scheduler:advance(0.2)
					t.expect(#fired).toBe(1)
					t.expect({ fired[1].name, fired[1].player, fired[1].payload.inventoryCount }).toEqual({
						"stateUpdate",
						player,
						collected,
					})
					runtime:stop()
					-- Nach stop feuern keine Scheduler-Aufrufe mehr: kein Nachfuellen, kein Zustand.
					runtime.game:dispatch(ctx, "collect")
					local itemsAfterStop = #(runtime.game.modules.collecting:instances(ctx) :: { any })
					scheduler:advance(10)
					t.expect(#fired).toBe(1)
					t.expect(#(runtime.game.modules.collecting:instances(ctx) :: { any })).toBe(itemsAfterStop)
				end)
			end
		)

		t.it(
			"116 client config: only visible data, no server-only keys; server config extends it consistently",
			function()
				local keys: { string } = {}
				allKeys(ClientConfig, "ClientConfig", keys)
				local forbidden: { string } = {}
				for _, path in keys do
					local last = string.match(path, "%.([^%.]+)$")
					if last ~= nil and table.find(SERVER_ONLY_KEYS, last) ~= nil then
						table.insert(forbidden, path)
					end
				end
				t.expect(forbidden).toEqual({})
				t.expect({ next(config.products), next(config.passes) }).toEqual({})
				t.expect(config.texts).toBe(ClientConfig.texts)
				for itemId, display in ClientConfig.items do
					local item = config.items[itemId]
					t.expect({ itemId, item.zoneId, item.asset, item.nameKey, item.rarity })
						.toEqual({ itemId, display.zoneId, display.asset, display.nameKey, display.rarity })
				end
				for zoneId, display in ClientConfig.zones do
					t.expect({ zoneId, config.zones[zoneId].order, config.zones[zoneId].condition })
						.toEqual({ zoneId, display.order, display.condition })
				end
				for dimension in config.upgrades do
					t.expect({ dimension, ClientConfig.upgrades[dimension] ~= nil }).toEqual({ dimension, true })
				end
			end
		)
	end)
end
