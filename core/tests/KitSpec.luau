--!strict
-- Tests 105-110: Kit (ReplicatedStorage.FactoryKit) - reine Logik kopflos, Darstellung in Test-Containern.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FactoryCore = ServerScriptService.FactoryCore
local FactoryKit = ReplicatedStorage.FactoryKit
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local GameServer = require(FactoryCore.server.GameServer)
local Log = require(FactoryCore.shared.Log)
local ItemView = require(FactoryKit.ItemView)
local HudModel = require(FactoryKit.HudModel)
local HudView = require(FactoryKit.HudView)
local FeedbackModel = require(FactoryKit.FeedbackModel)
local FeedbackView = require(FactoryKit.FeedbackView)
local OnboardingModel = require(FactoryKit.OnboardingModel)
local InputModel = require(FactoryKit.InputModel)
local Testbed = require(ReplicatedStorage.TestbedShared.Config)

local config = Testbed.config
local texts = config.texts

-- Ein echter Schnappschuss des Servers mit der Testbed-Config.
local function testbedSnapshot(): any
	local captured: any = nil
	local app = GameServer.compose(
		config,
		{
			storage = MemoryAdapter.new(),
			dataStoreKeyPrefix = "profile_",
			serverId = "server-a",
			clock = function()
				return 1000
			end,
			sleep = function() end,
			rng = Random.new(61),
			spawnPosition = function(): Vector3
				return Vector3.new(2, 1, 0)
			end,
			getPosition = function(): Vector3?
				return Vector3.new(0, 1, 0)
			end,
			canSell = function()
				return true
			end,
			ownsPass = function()
				return false
			end,
			analyticsSink = function() end,
			onLoadFailed = function() end,
			log = Log.new({ sink = function() end }),
			sendState = function(_ctx, snapshot)
				captured = snapshot
			end,
		} :: any
	)
	app:playerJoined({ userId = 101 }, "organic")
	app:flushState()
	return captured
end

local function with(snapshot: any, changes: { [string]: any }): any
	local copy = table.clone(snapshot)
	for key, value in changes do
		copy[key] = value
	end
	return copy
end

local function item(instanceId: string, itemTypeId: string, x: number): any
	return { instanceId = instanceId, itemTypeId = itemTypeId, zoneId = "zone_a", position = Vector3.new(x, 1, 0) }
end

local ITEM_ASSETS = { item_small = "item_small", item_medium = "item_medium" }

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("kit", function()
		t.it("105 ItemView diff and reconcile: one part per item, removals, stable instances, fallback", function()
			local diff = ItemView.diff(
				{ i1 = true, i2 = true },
				{ item("i2", "item_small", 0), item("i3", "item_small", 1) }
			)
			t.expect(#diff.add).toBe(1)
			t.expect(diff.add[1].instanceId).toBe("i3")
			t.expect(diff.remove).toEqual({ "i1" })

			local container = Instance.new("Folder")
			local ok, err = pcall(function()
				ItemView.reconcile(container, {
					item("i1", "item_small", 0),
					item("i2", "item_medium", 2),
					item("i3", "item_small", 4),
				}, Testbed.assetStyles, ITEM_ASSETS)
				t.expect(#container:GetChildren()).toBe(3)
				local kept = container:FindFirstChild("i1") :: Part
				t.expect(kept.Shape).toBe(Enum.PartType.Ball)
				t.expect({ kept.Anchored, kept.CanCollide }).toEqual({ true, false })
				t.expect(math.abs(kept.Position.Y - (1 + 0.6)) < 0.001).toBe(true)

				ItemView.reconcile(container, {
					item("i1", "item_small", 0),
					item("i3", "item_small", 4),
					item("i4", "item_unknown", 6),
				}, Testbed.assetStyles, ITEM_ASSETS)
				t.expect(#container:GetChildren()).toBe(3)
				t.expect(container:FindFirstChild("i1")).toBe(kept)
				t.expect(container:FindFirstChild("i2")).toBe(nil)
				local fallback = container:FindFirstChild("i4") :: Part
				t.expect(fallback.Size).toBe(Vector3.new(1, 1, 1))
				t.expect(fallback.Color:ToHex()).toBe((ItemView.FALLBACK_STYLE.color :: Color3):ToHex())

				ItemView.reconcile(container, {}, Testbed.assetStyles, ITEM_ASSETS)
				t.expect(#container:GetChildren()).toBe(0)
			end)
			container:Destroy()
			if not ok then
				error(err, 0)
			end
		end)

		t.it(
			"106 HudModel: coins, x / y with full flag, upgrades with cost or MAX, affordability, sell state",
			function()
				local base = testbedSnapshot()
				local upgrades = table.clone(base.upgrades)
				upgrades.capacity = { level = 3, maxLevel = 3 }
				local model =
					HudModel.build(with(base, { coins = 60, inventoryCount = 10, upgrades = upgrades }), config)

				t.expect(model.coinsText).toBe("Münzen: 60")
				t.expect(model.inventoryText).toBe("Inventar: 10 / 10 (voll)")
				t.expect(model.full).toBe(true)
				t.expect(model.sellEnabled).toBe(true)
				t.expect(model.upgrades).toEqual({
					{
						dimension = "capacity",
						name = "Kapazität",
						levelText = "Stufe 3/3",
						costText = "MAX",
						affordable = false,
						maxed = true,
					},
					{
						dimension = "range",
						name = "Reichweite",
						levelText = "Stufe 0/2",
						costText = "50 Münzen",
						affordable = true,
						maxed = false,
					},
					{
						dimension = "sell_bonus",
						name = "Verkaufsbonus",
						levelText = "Stufe 0/2",
						costText = "200 Münzen",
						affordable = false,
						maxed = false,
					},
				})
				t.expect({ model.nextZoneId, model.zoneText, model.canUnlock }).toEqual({
					"zone_b",
					"Zone B freischalten: 150 Münzen",
					false,
				})
				t.expect({ model.collectText, model.sellText }).toEqual({ "Einsammeln (E)", "Verkaufen (Q)" })

				local empty = HudModel.build(base, config)
				t.expect({ empty.inventoryText, empty.full, empty.sellEnabled })
					.toEqual({ "Inventar: 0 / 10", false, false })
			end
		)

		t.it("107 HudView: ScreenGui with touch-size buttons; buttons call exactly the matching intent", function()
			local calls: { { any } } = {}
			local intents = {
				collect = function()
					table.insert(calls, { "collect" })
					return true
				end,
				sell = function()
					table.insert(calls, { "sell" })
					return true
				end,
				buyUpgrade = function(_self, dimension: string)
					table.insert(calls, { "buyUpgrade", dimension })
					return true
				end,
				unlockZone = function(_self, zoneId: string)
					table.insert(calls, { "unlockZone", zoneId })
					return true
				end,
			}
			local container = Instance.new("Folder")
			local ok, err = pcall(function()
				local view = HudView.new(container, intents, Testbed.uiTokens)
				local base = testbedSnapshot()
				view:render(HudModel.build(with(base, { coins = 200, inventoryCount = 3 }), config))
				t.expect(view.gui:IsA("ScreenGui")).toBe(true)
				t.expect(view.gui.ResetOnSpawn).toBe(false)

				t.expect(view:press("collect")).toBe(true)
				t.expect(view:press("sell")).toBe(true)
				t.expect(view:press("upgrade:range")).toBe(true)
				t.expect(view:press("unlock")).toBe(true)
				t.expect(calls).toEqual({
					{ "collect" },
					{ "sell" },
					{ "buyUpgrade", "range" },
					{ "unlockZone", "zone_b" },
				})

				view:render(HudModel.build(base, config))
				t.expect(view:press("sell")).toBe(false)
				t.expect(#calls).toBe(4)

				local buttons = view:buttons()
				local count = 0
				for _, button in buttons do
					count += 1
					t.expect({ button.Name, button.Size.X.Offset >= HudView.MIN_TOUCH_SIZE })
						.toEqual({ button.Name, true })
					t.expect({ button.Name, button.Size.Y.Offset >= HudView.MIN_TOUCH_SIZE })
						.toEqual({ button.Name, true })
				end
				t.expect(count).toBe(6) -- collect, sell, unlock, drei Upgrades
				view:destroy()
				t.expect(#container:GetChildren()).toBe(0)
			end)
			container:Destroy()
			if not ok then
				error(err, 0)
			end
		end)

		t.it(
			"108 FeedbackModel detects collected, earned, upgraded, unlocked and full; nothing for equal snapshots",
			function()
				local base = testbedSnapshot()
				t.expect(FeedbackModel.compare(base, base)).toEqual({})

				local upgrades = table.clone(base.upgrades)
				upgrades.range = { level = 1, maxLevel = 2, nextCost = 150 }
				local zones = table.clone(base.zones)
				zones.zone_b = { unlocked = true, order = 2 }
				local after = with(base, { inventoryCount = 10, coins = 35, upgrades = upgrades, zones = zones })
				t.expect(FeedbackModel.compare(base, after)).toEqual({
					collected = 10,
					earned = 35,
					upgraded = "range",
					unlocked = "zone_b",
					full = true,
				})
				-- Bereits voll: kein erneutes "full".
				t.expect(FeedbackModel.compare(after, with(after, { coins = 40 }))).toEqual({ earned = 5 })
				t.expect(FeedbackView.messages({ collected = 3, earned = 12 }, texts)).toEqual({ "+3", "+12 Münzen" })
			end
		)

		t.it("109 OnboardingModel runs through a snapshot chain to done; custom steps from data are used", function()
			local base = testbedSnapshot()
			local onboarding = OnboardingModel.new()
			t.expect((onboarding:update(base) :: any).id).toBe("collect")
			t.expect((onboarding:current() :: any).target).toBe("item")

			local collected = with(base, { inventoryCount = 4 })
			t.expect((onboarding:update(collected) :: any).id).toBe("sell")
			t.expect((onboarding:update(with(collected, { inventoryCount = 0 })) :: any).id).toBe("sell")
			local sold = with(base, { inventoryCount = 0, coins = 12 })
			t.expect((onboarding:update(sold) :: any).id).toBe("upgrade")

			local upgrades = table.clone(base.upgrades)
			upgrades.range = { level = 1, maxLevel = 2, nextCost = 150 }
			t.expect((onboarding:update(with(sold, { upgrades = upgrades })) :: any).id).toBe("unlockZone")
			local zones = table.clone(base.zones)
			zones.zone_b = { unlocked = true, order = 2 }
			t.expect(onboarding:update(with(sold, { upgrades = upgrades, zones = zones }))).toBe(nil)
			t.expect(onboarding:isDone()).toBe(true)

			local custom = OnboardingModel.new({
				{ id = "first", textKey = "custom_first", target = "none", condition = "inventory" },
			})
			t.expect((custom:update(base) :: any).textKey).toBe("custom_first")
			t.expect(custom:update(collected)).toBe(nil)
		end)

		t.it(
			"110 InputModel: key and gamepad mapping; auto-collect only with an item in range, at most every 0.25 s",
			function()
				local now = 0
				local calls: { string } = {}
				local model = InputModel.new({
					intents = {
						collect = function()
							table.insert(calls, "collect")
							return true
						end,
						sell = function()
							table.insert(calls, "sell")
							return true
						end,
					},
					clock = function()
						return now
					end,
				})
				t.expect({ model:onInput("E"), model:onInput("Q"), model:onInput("ButtonX"), model:onInput("ButtonY") })
					.toEqual({
						"collect",
						"sell",
						"collect",
						"sell",
					})
				t.expect(model:onInput("F")).toBe(nil)
				t.expect(calls).toEqual({ "collect", "sell", "collect", "sell" })
				table.clear(calls)

				local snapshot = { range = 10, items = { item("i1", "item_small", 9) } }
				local origin = Vector3.new(0, 1, 0)
				t.expect(model:tick(snapshot, Vector3.new(30, 1, 0))).toBe(false)
				t.expect(model:tick(snapshot, origin)).toBe(true)
				now += 0.2
				t.expect(model:tick(snapshot, origin)).toBe(false)
				now += 0.05
				t.expect(model:tick(snapshot, origin)).toBe(true)
				t.expect(model:tick({ range = 10, items = {} }, origin)).toBe(false)
				t.expect(model:tick(snapshot, nil)).toBe(false)
				t.expect(calls).toEqual({ "collect", "collect" })
			end
		)
	end)
end
