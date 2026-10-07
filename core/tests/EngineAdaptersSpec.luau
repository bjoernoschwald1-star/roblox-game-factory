--!strict
-- Tests 87-90: echte Adapter, soweit ohne Spieler testbar. Tests mit echten Instanzen raeumen immer auf.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local WorldAdapter = require(FactoryCore.server.Engine.WorldAdapter)
local RemoteBinder = require(FactoryCore.server.Engine.RemoteBinder)
local AnalyticsAdapter = require(FactoryCore.server.Engine.AnalyticsAdapter)
local PlayersAdapter = require(FactoryCore.server.Engine.PlayersAdapter)
local Schema = require(FactoryCore.server.Config.Schema)
local Log = require(FactoryCore.shared.Log)
local SampleConfig = require(ServerScriptService.FactoryCoreTests.fixtures.SampleConfig)

-- Fuehrt body aus und raeumt danach in jedem Fall auf; Fehler werden erst nach dem Aufraeumen weitergegeben.
local function withCleanup(body: () -> (), cleanup: () -> ())
	local ok, err = pcall(body)
	cleanup()
	if not ok then
		error(err, 0)
	end
end

local function part(name: string, size: Vector3, cframe: CFrame, parent: Instance): Part
	local created = Instance.new("Part")
	created.Name = name
	created.Anchored = true
	created.Size = size
	created.CFrame = cframe
	created.Parent = parent
	return created
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("engine adapters", function()
		t.it("87 real WorldAdapter: spawn on the (rotated) top face, sell areas, validateWorld", function()
			t.expect(workspace:FindFirstChild(WorldAdapter.ROOT_NAME)).toBe(nil)
			local root = Instance.new("Folder")
			withCleanup(function()
				root.Name = WorldAdapter.ROOT_NAME
				local zones = Instance.new("Folder")
				zones.Name = "Zones"
				zones.Parent = root
				local sellAreas = Instance.new("Folder")
				sellAreas.Name = "SellAreas"
				sellAreas.Parent = root
				local tilted = CFrame.new(100, 5, -40) * CFrame.Angles(math.rad(20), math.rad(35), math.rad(-10))
				local zoneA = part("zone_a", Vector3.new(20, 2, 10), tilted, zones)
				part("zone_b", Vector3.new(30, 1, 30), CFrame.new(0, 0, 200), zones)
				local zoneC = part("zone_c", Vector3.new(30, 1, 30), CFrame.new(0, 0, 400), zones)
				part("sell_main", Vector3.new(10, 10, 10), CFrame.new(0, 0, 0), sellAreas)
				root.Parent = workspace

				local world = WorldAdapter.new()
				t.expect(world:validateWorld(SampleConfig())).toEqual({})
				local rng = Random.new(5)
				local outside = 0
				for _ = 1, 200 do
					local position = world:spawnPosition("zone_a", rng)
					local localPoint = zoneA.CFrame:PointToObjectSpace(position)
					if
						math.abs(localPoint.X) > 10.001
						or math.abs(localPoint.Z) > 5.001
						or math.abs(localPoint.Y - 1) > 0.001
					then
						outside += 1
					end
				end
				t.expect(outside).toBe(0)

				t.expect(world:isInSellArea(Vector3.new(1, 2, -3))).toBe(true)
				t.expect(world:isInSellArea(Vector3.new(20, 0, 0))).toBe(false)
				t.expect(world:isInSellArea(Vector3.new(0, 6, 0))).toBe(false)

				zoneC:Destroy()
				t.expect(world:validateWorld(SampleConfig())).toEqual({ "FactoryWorld.Zones.zone_c" })
			end, function()
				root:Destroy()
			end)
			t.expect(workspace:FindFirstChild(WorldAdapter.ROOT_NAME)).toBe(nil)
		end)

		t.it(
			"88 real RemoteBinder: exactly four RemoteEvents in ReplicatedStorage.FactoryRemotes, no duplicates",
			function()
				t.expect(ReplicatedStorage:FindFirstChild(RemoteBinder.FOLDER_NAME)).toBe(nil)
				local connections = {}
				withCleanup(function()
					for _ = 1, 2 do
						local binder = RemoteBinder.new()
						for _, name in Schema.REMOTES do
							table.insert(connections, binder:bind(name, function() end))
						end
					end
					local folder = ReplicatedStorage:FindFirstChild(RemoteBinder.FOLDER_NAME) :: Instance
					local names = {}
					for _, child in folder:GetChildren() do
						t.expect(child:IsA("RemoteEvent")).toBe(true)
						table.insert(names, child.Name)
					end
					table.sort(names)
					t.expect(names).toEqual({ "buyUpgrade", "collect", "sell", "unlockZone" })
				end, function()
					for _, connection in connections do
						connection:Disconnect()
					end
					local folder = ReplicatedStorage:FindFirstChild(RemoteBinder.FOLDER_NAME)
					if folder ~= nil then
						folder:Destroy()
					end
				end)
				t.expect(ReplicatedStorage:FindFirstChild(RemoteBinder.FOLDER_NAME)).toBe(nil)
			end
		)

		t.it("89 AnalyticsAdapter maps funnel and custom events; departed players are dropped", function()
			local calls: { { any } } = {}
			local service = {
				LogOnboardingFunnelStepEvent = function(_self, player, step, stepName, fields)
					table.insert(calls, { "funnel", player.UserId, step, stepName, fields })
				end,
				LogCustomEvent = function(_self, player, eventName, value, fields)
					table.insert(calls, { "custom", player.UserId, eventName, value, fields })
				end,
			}
			local present = { [101] = { UserId = 101 } }
			local adapter = AnalyticsAdapter.new({
				analyticsService = service,
				findPlayer = function(userId: number)
					return present[userId]
				end,
			})
			local base = { gameId = "sample_game", configVersion = "1.0.0", userId = 101 }
			local function with(extra: { [string]: any }): { [string]: any }
				local fields = table.clone(base)
				for key, value in extra do
					fields[key] = value
				end
				return fields
			end

			adapter.sink("first_collect", with({ funnelStep = 2 }))
			adapter.sink("session_end", with({ durationSeconds = 90 }))
			adapter.sink("purchase_success", with({ role = "coins_small" }))
			adapter.sink("zone_unlock", with({ zoneIndex = 2, funnelStep = 5 }))
			local commonFields = { CustomField01 = "1.0.0", CustomField03 = "sample_game" }
			local roleFields = { CustomField01 = "1.0.0", CustomField02 = "coins_small", CustomField03 = "sample_game" }
			t.expect(calls).toEqual({
				{ "funnel", 101, 2, "first_collect", commonFields },
				{ "custom", 101, "first_collect", 1, commonFields },
				{ "custom", 101, "session_end", 90, commonFields },
				{ "custom", 101, "purchase_success", 1, roleFields },
				{ "funnel", 101, 5, "zone_unlock", commonFields },
				{ "custom", 101, "zone_unlock", 2, commonFields },
			})

			local called = pcall(adapter.sink, "first_sell", with({ userId = 999, funnelStep = 3 }))
			t.expect(called).toBe(true)
			t.expect(#calls).toBe(6)
		end)

		t.it("90 joinSource: paid, JSON organic, nonsense, missing and throwing GetJoinData", function()
			local function playerWith(getJoinData: (self: any) -> any): any
				return { UserId = 1, GetJoinData = getJoinData }
			end
			local sources = {
				PlayersAdapter.joinSourceOf(playerWith(function()
					return { LaunchData = "paid" }
				end)),
				PlayersAdapter.joinSourceOf(playerWith(function()
					return { LaunchData = '{"source":"organic","campaign":"x"}' }
				end)),
				PlayersAdapter.joinSourceOf(playerWith(function()
					return { LaunchData = "{not json" }
				end)),
				PlayersAdapter.joinSourceOf(playerWith(function()
					return {}
				end)),
				PlayersAdapter.joinSourceOf(playerWith(function(): any
					error("join data unavailable")
				end)),
			}
			t.expect(sources).toEqual({ "paid", "organic", "unknown", "unknown", "unknown" })
		end)

		t.it("92 AnalyticsAdapter errors: funnel failure propagates, custom failure after funnel only warns", function()
			local failFunnel, failCustom = false, false
			local funnelCalls, customCalls = 0, 0
			local warnings: { string } = {}
			local adapter = AnalyticsAdapter.new({
				analyticsService = {
					LogOnboardingFunnelStepEvent = function()
						funnelCalls += 1
						if failFunnel then
							error("funnel service down")
						end
					end,
					LogCustomEvent = function()
						customCalls += 1
						if failCustom then
							error("custom service down")
						end
					end,
				},
				findPlayer = function(userId: number)
					return { UserId = userId }
				end,
				log = Log.new({
					sink = function(message: string)
						table.insert(warnings, message)
					end,
				}),
			})
			local funnelFields = { gameId = "sample_game", configVersion = "1.0.0", userId = 101, funnelStep = 2 }
			local plainFields = { gameId = "sample_game", configVersion = "1.0.0", userId = 101 }

			failFunnel = true
			t.expect((pcall(adapter.sink, "first_collect", funnelFields))).toBe(false)
			t.expect({ funnelCalls, customCalls }).toEqual({ 1, 0 })

			failFunnel, failCustom = false, true
			t.expect((pcall(adapter.sink, "first_collect", funnelFields))).toBe(true)
			t.expect({ funnelCalls, customCalls }).toEqual({ 2, 1 })
			t.expect(#warnings).toBe(1)

			t.expect((pcall(adapter.sink, "inventory_full", plainFields))).toBe(false)
			t.expect({ funnelCalls, customCalls }).toEqual({ 2, 2 })
			t.expect(#warnings).toBe(1)
		end)
	end)
end
