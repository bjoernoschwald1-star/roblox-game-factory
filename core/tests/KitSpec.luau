--!strict
-- Tests 105-110, 117-128, 132: Kit (ReplicatedStorage.FactoryKit) - reine Logik kopflos, Darstellung in
-- Test-Containern. Server-Schnappschuesse mit der Testbed-ServerConfig, Darstellung mit der ClientConfig.
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
local OnboardingView = require(FactoryKit.OnboardingView)
local HudLayout = require(FactoryKit.HudLayout)
local Text = require(FactoryKit.Text)
local CollectFx = require(FactoryKit.CollectFx)
local LightingProfile = require(FactoryKit.LightingProfile)
local ClientConfig = require(ReplicatedStorage.TestbedShared.ClientConfig)
local ServerConfig = require(ServerScriptService.TestbedServerUnderTest.ServerConfig)

local config: any = ServerConfig
local texts = ClientConfig.texts

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
				}, ClientConfig.assetStyles, ITEM_ASSETS)
				t.expect(#container:GetChildren()).toBe(3)
				local kept = container:FindFirstChild("i1") :: Part
				t.expect(kept.Shape).toBe(Enum.PartType.Ball)
				t.expect({ kept.Anchored, kept.CanCollide }).toEqual({ true, false })
				t.expect(math.abs(kept.Position.Y - (1 + 0.6)) < 0.001).toBe(true)

				ItemView.reconcile(container, {
					item("i1", "item_small", 0),
					item("i3", "item_small", 4),
					item("i4", "item_unknown", 6),
				}, ClientConfig.assetStyles, ITEM_ASSETS)
				t.expect(#container:GetChildren()).toBe(3)
				t.expect(container:FindFirstChild("i1")).toBe(kept)
				t.expect(container:FindFirstChild("i2")).toBe(nil)
				local fallback = container:FindFirstChild("i4") :: Part
				t.expect(fallback.Size).toBe(Vector3.new(1, 1, 1))
				t.expect(fallback.Color:ToHex()).toBe((ItemView.FALLBACK_STYLE.color :: Color3):ToHex())

				ItemView.reconcile(container, {}, ClientConfig.assetStyles, ITEM_ASSETS)
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
				t.expect(model.collectEnabled).toBe(false)
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
					"Zone B: 150 Münzen",
					false,
				})
				t.expect(model.unlockText).toBe("Freischalten")
				t.expect({ model.collectText, model.sellText }).toEqual({ "Einsammeln (E)", "Verkaufen (Q)" })

				local empty = HudModel.build(base, config)
				t.expect({ empty.inventoryText, empty.full, empty.sellEnabled, empty.collectEnabled })
					.toEqual({ "Inventar: 0 / 10", false, false, true })
			end
		)

		t.it("107 HudView: compact HUD; buttons call exactly the matching intent; upgrades window on demand", function()
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
				local view = HudView.new(container, intents, ClientConfig.uiTokens)
				local base = testbedSnapshot()
				view:render(HudModel.build(with(base, { coins = 200, inventoryCount = 3 }), config))
				t.expect(view.gui:IsA("ScreenGui")).toBe(true)
				t.expect(view.gui.ResetOnSpawn).toBe(false)

				-- Upgrade-Fenster erst auf Knopfdruck; Umschalten sendet keine Absicht.
				t.expect(view:windowOpen()).toBe(false)
				t.expect(view:press("upgrades")).toBe(true)
				t.expect(view:windowOpen()).toBe(true)
				t.expect(view:press("upgradesClose")).toBe(true)
				t.expect(view:windowOpen()).toBe(false)

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
				for _ in buttons do
					count += 1
				end
				t.expect(count).toBe(8) -- collect, sell, unlock, upgrades, upgradesClose, drei Upgrades
				-- Rand-Knoepfe: Skalenwerte, feste Pixelgroesse ueber UISizeConstraint, mindestens Touch-Groesse.
				for _, name in { "collect", "sell", "unlock", "upgrades" } do
					local button = buttons[name]
					local limit = button:FindFirstChildOfClass("UISizeConstraint") :: UISizeConstraint
					t.expect({ name, button.Size.X.Offset, button.Size.Y.Offset }).toEqual({ name, 0, 0 })
					t.expect({ name, limit.MinSize.Y >= 40, limit.MinSize == limit.MaxSize })
						.toEqual({ name, true, true })
				end
				-- Upgrade-Knoepfe liegen im Fenster.
				t.expect(buttons["upgrade:range"]:IsDescendantOf(view:element("window") :: Instance)).toBe(true)
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

		t.it("117 HudModel zone branches: upgradeLevel, coinsAtLeast and all zones unlocked", function()
			local base = testbedSnapshot()
			local zones = table.clone(base.zones)
			zones.zone_b = { unlocked = true, order = 2 }
			local upgrades = table.clone(base.upgrades)
			upgrades.capacity = { level = 1, maxLevel = 3, nextCost = 300 }
			local level = HudModel.build(with(base, { zones = zones, upgrades = upgrades }), ClientConfig)
			t.expect({ level.nextZoneId, level.zoneText, level.canUnlock })
				.toEqual({ "zone_c", "Zone C: Kapazität Stufe 2", false })
			local reached = table.clone(upgrades)
			reached.capacity = { level = 2, maxLevel = 3, nextCost = 900 }
			t.expect(HudModel.build(with(base, { zones = zones, upgrades = reached }), ClientConfig).canUnlock)
				.toBe(true)

			local coinsConfig = table.clone(ClientConfig) :: any
			coinsConfig.zones = table.clone(ClientConfig.zones)
			coinsConfig.zones.zone_b =
				{ order = 2, nameKey = "zone_b_name", condition = { type = "coinsAtLeast", amount = 100 } }
			local poor = HudModel.build(with(base, { coins = 99 }), coinsConfig)
			t.expect({ poor.zoneText, poor.canUnlock }).toEqual({ "Zone B: ab 100 Münzen", false })
			t.expect(HudModel.build(with(base, { coins = 100 }), coinsConfig).canUnlock).toBe(true)

			local allZones = table.clone(zones)
			allZones.zone_c = { unlocked = true, order = 3 }
			local done = HudModel.build(with(base, { coins = 5000, zones = allZones }), ClientConfig)
			t.expect({ done.nextZoneId, done.zoneText, done.canUnlock }).toEqual({ nil, "Alle Zonen frei", false })
		end)

		t.it(
			"118 HudView: locked upgrade and unlock presses send nothing; unlock without a next zone is hidden",
			function()
				local calls: { any } = {}
				local intents = {
					collect = function()
						table.insert(calls, "collect")
						return true
					end,
					sell = function()
						table.insert(calls, "sell")
						return true
					end,
					buyUpgrade = function(_self, dimension: string)
						table.insert(calls, "upgrade:" .. dimension)
						return true
					end,
					unlockZone = function(_self, zoneId: string)
						table.insert(calls, "unlock:" .. zoneId)
						return true
					end,
				}
				local container = Instance.new("Folder")
				local ok, err = pcall(function()
					local view = HudView.new(container, intents, ClientConfig.uiTokens)
					local base = testbedSnapshot()
					view:render(HudModel.build(with(base, { coins = 0 }), ClientConfig))
					t.expect(view:press("upgrade:range")).toBe(false)
					t.expect(view:press("upgrade:capacity")).toBe(false)
					t.expect(view:press("unlock")).toBe(false)
					-- Ein Rand-Knopf zeigt die Bedingung der naechsten Zone.
					local unlockButton = view:buttons().unlock
					t.expect({ unlockButton.Visible, unlockButton.Active, unlockButton.Text })
						.toEqual({ true, false, "Zone B: 150 Münzen" })

					local zones = table.clone(base.zones)
					zones.zone_b = { unlocked = true, order = 2 }
					zones.zone_c = { unlocked = true, order = 3 }
					view:render(HudModel.build(with(base, { coins = 5000, zones = zones }), ClientConfig))
					t.expect(unlockButton.Visible).toBe(false)
					t.expect(view:press("unlock")).toBe(false)
					t.expect(view:press("upgrade:range")).toBe(true)
					t.expect(calls).toEqual({ "upgrade:range" })
					-- Volles Inventar: Einsammeln gesperrt (nur Anzeige), Schrift dunkel auf Hervorhebung.
					view:render(HudModel.build(with(base, { inventoryCount = 10 }), ClientConfig))
					t.expect(view:press("collect")).toBe(false)
					t.expect(calls).toEqual({ "upgrade:range" })
					local inventory = view:element("inventory") :: TextLabel
					t.expect({ inventory.BackgroundColor3, inventory.TextColor3 })
						.toEqual({ ClientConfig.uiTokens.highlight, ClientConfig.uiTokens.highlightText })
					view:destroy()
				end)
				container:Destroy()
				if not ok then
					error(err, 0)
				end
			end
		)

		t.it(
			"119 HudLayout: compact edge HUD free of overlaps, reserved zones and screen centre in ten viewports",
			function()
				local viewports = {
					Vector2.new(456, 784),
					Vector2.new(844, 390),
					Vector2.new(768, 1024),
					Vector2.new(1024, 768),
					Vector2.new(1180, 820),
					Vector2.new(960, 600),
					Vector2.new(1280, 720),
					Vector2.new(1366, 768),
					Vector2.new(1736, 793),
					Vector2.new(1920, 1080),
				}
				for _, viewport in viewports do
					for _, topInset in { 36, 58 } do
						t.expect({ viewport, topInset, HudLayout.check(viewport, topInset, 3) })
							.toEqual({ viewport, topInset, {} })
					end
				end
				t.expect(HudLayout.presetFor(Vector2.new(456, 726))).toBe("portrait")
				t.expect(HudLayout.presetFor(Vector2.new(844, 332))).toBe("landscape")
				t.expect(HudLayout.presetFor(Vector2.new(768, 966))).toBe("tabletPortrait")
				t.expect(HudLayout.presetFor(Vector2.new(960, 542))).toBe("tablet")
				t.expect(HudLayout.presetFor(Vector2.new(1280, 662))).toBe("wide")
				-- Spielerliste nur auf grossen Flaechen; Touch-Zonen nicht am Desktop.
				local phone = HudLayout.reserved(Vector2.new(844, 332))
				t.expect({ phone.playerList == nil, phone.jump ~= nil, phone.thumb ~= nil })
					.toEqual({ true, true, true })
				local desk = HudLayout.reserved(Vector2.new(1280, 662))
				t.expect({ desk.playerList ~= nil, desk.jump == nil, desk.thumb == nil }).toEqual({ true, true, true })
				local playerList = desk.playerList :: HudLayout.Rect
				t.expect({ playerList.w >= 320, playerList.h >= 312 }).toEqual({ true, true })
				-- Runde Aktionsknoepfe: am PC klein, auf dem Handy daumengross, auf dem Tablet groesser.
				local sizes = {}
				for _, area in { Vector2.new(1280, 662), Vector2.new(456, 726), Vector2.new(1024, 710) } do
					table.insert(sizes, HudLayout.rects(area).collect.w)
				end
				t.expect(sizes).toEqual({ 80, 72, 88 })
				-- Ueberlappung wird erkannt (Gegenprobe).
				t.expect(HudLayout.overlaps({ x = 0, y = 0, w = 10, h = 10 }, { x = 9, y = 9, w = 5, h = 5 }))
					.toBe(true)
				t.expect(HudLayout.overlaps({ x = 0, y = 0, w = 10, h = 10 }, { x = 10, y = 0, w = 5, h = 5 }))
					.toBe(false)

				local container = Instance.new("Folder")
				local ok, err = pcall(function()
					local noop = function()
						return true
					end
					local intents: any = { collect = noop, sell = noop, buyUpgrade = noop, unlockZone = noop }
					local view = HudView.new(container, intents, ClientConfig.uiTokens)
					view:render(HudModel.build(testbedSnapshot(), ClientConfig))
					local area = Vector2.new(456, 726)
					t.expect(view:applyLayout(area)).toBe("portrait")
					local specs = HudLayout.specs("portrait", nil, area)
					for _, name in { "coins", "inventory", "unlock", "upgrades", "collect", "sell", "window" } do
						local element = view:element(name) :: GuiObject
						local s = specs[name]
						t.expect({ name, element.Position, element.Size }).toEqual({
							name,
							UDim2.fromScale(s.position.X, s.position.Y),
							UDim2.fromScale(s.size.X, s.size.Y),
						})
					end
					t.expect(view:applyLayout(Vector2.new(1280, 662))).toBe("wide")
					view:destroy()
				end)
				container:Destroy()
				if not ok then
					error(err, 0)
				end
			end
		)

		t.it("120 Text.format keeps a missing placeholder visible; lookup falls back to the key", function()
			t.expect(Text.format("{a} und {b}", { a = 1 })).toBe("1 und {b}")
			t.expect(Text.format("{a}", nil)).toBe("{a}")
			t.expect(Text.format(nil, { a = 1 })).toBe("")
			t.expect(Text.lookup(texts, "no_such_key")).toBe("no_such_key")
			t.expect(Text.lookup(nil, "hud_coins", { coins = 3 })).toBe("hud_coins")
		end)

		t.it("121 InputModel: no auto-collect while the inventory is full", function()
			local calls = 0
			local model = InputModel.new({
				intents = {
					collect = function()
						calls += 1
						return true
					end,
					sell = function()
						return true
					end,
				},
				clock = function()
					return 0
				end,
			})
			local items = { item("i1", "item_small", 1) }
			local origin = Vector3.new(0, 1, 0)
			t.expect(model:tick({ range = 10, items = items, inventoryCount = 10, capacity = 10 }, origin)).toBe(false)
			t.expect(calls).toBe(0)
			t.expect(model:tick({ range = 10, items = items, inventoryCount = 9, capacity = 10 }, origin)).toBe(true)
			t.expect(calls).toBe(1)
		end)

		t.it(
			"122 OnboardingModel skips steps already reached on the first snapshot; full hint points to selling",
			function()
				local base = testbedSnapshot()
				local upgrades = table.clone(base.upgrades)
				upgrades.range = { level = 1, maxLevel = 2, nextCost = 150 }
				local zones = table.clone(base.zones)
				zones.zone_b = { unlocked = true, order = 2 }

				local returning = OnboardingModel.new()
				t.expect(returning:update(with(base, { upgrades = upgrades, zones = zones }))).toBe(nil)
				t.expect(returning:isDone()).toBe(true)

				local upgraded = OnboardingModel.new()
				t.expect((upgraded:update(with(base, { upgrades = upgrades })) :: any).id).toBe("unlockZone")

				local current = OnboardingModel.DEFAULT_STEPS[2]
				t.expect({
					OnboardingModel.displayStep(true, true, current),
					OnboardingModel.displayStep(false, true, current),
					OnboardingModel.displayStep(false, false, current),
				}).toEqual({ nil, OnboardingModel.FULL_HINT, current })

				local fresh = OnboardingModel.new()
				t.expect((fresh:update(base) :: any).id).toBe("collect")
				-- Nur der erste Schnappschuss ueberspringt; danach gilt die normale Kette.
				t.expect((fresh:update(with(base, { upgrades = upgrades })) :: any).id).toBe("collect")

				t.expect({ OnboardingModel.FULL_HINT.target, OnboardingModel.FULL_HINT.textKey })
					.toEqual({ "sell", "hint_full" })
				t.expect(type(texts[OnboardingModel.FULL_HINT.textKey])).toBe("string")
			end
		)

		t.it(
			"123 OnboardingView: small hint at the top that hides after a few seconds; beam only with a target",
			function()
				local guiParent = Instance.new("Folder")
				local world = Instance.new("Folder")
				world.Parent = workspace
				local ok, err = pcall(function()
					local now = 0
					local view = OnboardingView.new(guiParent, world, nil, function()
						return now
					end)
					local root = Instance.new("Part")
					root.Anchored = true
					root.Parent = world
					local step = OnboardingModel.DEFAULT_STEPS[1]
					view:update(step, texts, nil, nil)
					t.expect({ view:hint().Visible, view:hint().Text, view:beam().Enabled })
						.toEqual({ true, texts.onboarding_collect, false })
					t.expect(view:hint().TextScaled).toBe(true)
					-- Lage aus HudLayout "hint" fuer die Flaeche, die das ScreenGui im Test-Container meldet.
					local hintGui = view:hint().Parent :: ScreenGui
					local area = hintGui.AbsoluteSize
					local hintSpec = HudLayout.specs(HudLayout.presetFor(area), 0, area).hint
					t.expect({ view:hint().Position, view:hint().Size }).toEqual({
						UDim2.fromScale(hintSpec.position.X, hintSpec.position.Y),
						UDim2.fromScale(hintSpec.size.X, hintSpec.size.Y),
					})
					view:update(step, texts, root, Vector3.new(10, 0, 0))
					t.expect(view:beam().Enabled).toBe(true)
					local source = view:beam().Attachment0
					t.expect(source ~= nil and source.Parent == root).toBe(true)
					-- Nach HINT_SECONDS verschwindet der Hinweis, der Strahl bleibt; neuer Text zeigt ihn wieder.
					now += OnboardingView.HINT_SECONDS + 0.1
					view:update(step, texts, root, Vector3.new(10, 0, 0))
					t.expect({ view:hint().Visible, view:beam().Enabled }).toEqual({ false, true })
					view:update(OnboardingModel.DEFAULT_STEPS[2], texts, root, Vector3.new(10, 0, 0))
					t.expect(view:hint().Visible).toBe(true)
					view:update(nil, texts, root, Vector3.new(10, 0, 0))
					t.expect({ view:hint().Visible, view:beam().Enabled }).toEqual({ false, false })
					view:destroy()
					t.expect(#guiParent:GetChildren()).toBe(0)
					t.expect(#world:GetChildren()).toBe(1) -- nur noch der Wurzel-Part
				end)
				guiParent:Destroy()
				world:Destroy()
				if not ok then
					error(err, 0)
				end
			end
		)

		t.it("124 FeedbackModel: rarest new item is found; wow from epic, legendary stronger", function()
			local rarities: { [string]: string } = {}
			for itemId, display in ClientConfig.items do
				rarities[itemId] = display.rarity
			end
			local base = with(testbedSnapshot(), { inventory = {}, inventoryCount = 0 })
			local epic = with(base, { inventory = { item_small = 2, item_a_epic = 1 }, inventoryCount = 3 })
			local events = FeedbackModel.compare(base, epic, rarities)
			t.expect({ events.collected, events.found, events.foundRarity }).toEqual({ 3, "item_a_epic", "epic" })
			local legendary = with(epic, {
				inventory = { item_small = 2, item_a_epic = 2, item_a_legendary = 1 },
				inventoryCount = 5,
			})
			t.expect(FeedbackModel.compare(epic, legendary, rarities).foundRarity).toBe("legendary")
			local common = with(base, { inventory = { item_small = 1 }, inventoryCount = 1 })
			t.expect(FeedbackModel.compare(base, common, rarities).found).toBe(nil)
			t.expect(FeedbackModel.compare(base, epic).found).toBe(nil)
			t.expect({
				FeedbackModel.isWow("common"),
				FeedbackModel.isWow("rare"),
				FeedbackModel.isWow("epic"),
				FeedbackModel.isWow("legendary"),
				FeedbackModel.wowLevel("epic"),
				FeedbackModel.wowLevel("legendary"),
			}).toEqual({ false, false, true, true, 1, 2 })
		end)

		t.it(
			"125 FeedbackView: billboards at the character sized by rarity; wow banner; effect table and sounds",
			function()
				local container = Instance.new("Folder")
				local world = Instance.new("Folder")
				world.Parent = workspace
				local ok, err = pcall(function()
					local root = Instance.new("Part")
					root.Anchored = true
					root.Parent = world
					local pending: { () -> () } = {}
					local camera = Instance.new("Camera")
					camera.FieldOfView = 70
					local view = FeedbackView.new(container, ClientConfig.effects, 1, {
						camera = camera,
						adornee = function()
							return root
						end,
						schedule = function(_seconds: number, callback: () -> ())
							table.insert(pending, callback)
						end,
					})
					local lines = view:show(
						{ collected = 2, earned = 5, found = "Funkelndes Objekt", foundRarity = "epic" },
						texts
					)
					t.expect(lines).toEqual({ "+2", "+5 Münzen" })
					local billboards = container:FindFirstChild("FactoryFeedbackBillboards") :: Folder
					local popups = billboards:GetChildren()
					t.expect(#popups).toBe(2)
					local sizes: { number } = {}
					for _, popup in popups do
						local billboard = popup :: BillboardGui
						t.expect(billboard.Adornee).toBe(root)
						table.insert(sizes, billboard.Size.X.Offset)
					end
					table.sort(sizes)
					t.expect(sizes).toEqual({ 200, math.floor(200 * FeedbackView.POPUP_SCALE[3]) })
					local banner = view:banner() :: TextLabel
					t.expect(banner.Text).toBe("Episch! Funkelndes Objekt")
					-- Banner liegt auf dem Platz des Onboarding-Hinweises.
					local bannerGui = banner.Parent :: ScreenGui
					local bannerArea = bannerGui.AbsoluteSize
					local hintSpec = HudLayout.specs(HudLayout.presetFor(bannerArea), 0, bannerArea).hint
					t.expect(banner.Position).toBe(UDim2.fromScale(hintSpec.position.X, hintSpec.position.Y))
					-- Zweiter Fund waehrend des Sichtfeld-Impulses: kein Aufsummieren, danach wieder der Basiswert.
					view:show({ found = "Strahlendes Objekt", foundRarity = "legendary" }, texts)
					t.expect(view:banner() ~= banner).toBe(true)
					t.expect(container:FindFirstChildWhichIsA("Sound", true)).toBe(nil)
					for _, callback in pending do
						callback()
					end
					t.expect(#billboards:GetChildren()).toBe(0)
					t.expect(view:banner()).toBe(nil)
					t.expect(camera.FieldOfView).toBe(70)
					camera:Destroy()
					t.expect(FeedbackView.bannerText({ found = "x", foundRarity = "rare" }, texts)).toBe(nil)
					t.expect(FeedbackView.bannerText({ found = "X", foundRarity = "legendary" }, texts))
						.toBe("Legendär! X")

					-- Effekt-Tabelle des Games: eigener Text-Schluessel; Sound nur mit geliefertem SoundId.
					t.expect(FeedbackView.messages({ collected = 1 }, texts, { collected = { textKey = "hud_full" } }))
						.toEqual({ "(voll)" })
					view:destroy()
					t.expect(#container:GetChildren()).toBe(0)
					local withSound = FeedbackView.new(
						container,
						{
							sounds = { collected = "rbxasset://sounds/electronicpingshort.wav" },
						},
						1,
						{
							schedule = function() end,
						}
					)
					withSound:show({ collected = 1 }, texts)
					t.expect(container:FindFirstChildWhichIsA("Sound", true) ~= nil).toBe(true)
					withSound:destroy()
					t.expect(#container:GetChildren()).toBe(0)
				end)
				container:Destroy()
				world:Destroy()
				if not ok then
					error(err, 0)
				end
			end
		)

		t.it(
			"126 ItemView rarity: size, material, highlight from rare, light and sparkles from epic, capped",
			function()
				local legendaryStyle = ItemView.rarityStyle("legendary", ClientConfig.rarityStyles)
				t.expect({ legendaryStyle.material, legendaryStyle.scale, legendaryStyle.accent })
					.toEqual({ "Neon", 1.5, ClientConfig.rarityStyles.legendary.accent })
				t.expect(ItemView.rarityStyle("mythic", nil)).toEqual(ItemView.DEFAULT_RARITY_STYLES.common)
				t.expect(ItemView.pose(Vector3.new(1, 2, 3), 0, 0, 0, 5)).toEqual(CFrame.new(1, 2, 3))

				local assets: { [string]: string } = {}
				local rarities: { [string]: string } = {}
				for itemId, display in ClientConfig.items do
					assets[itemId] = display.asset
					rarities[itemId] = display.rarity
				end
				local items = {}
				for index = 1, 20 do
					table.insert(items, item("l" .. index, "item_a_legendary", index * 3))
				end
				table.insert(items, item("c1", "item_small", -5))
				table.insert(items, item("r1", "item_a_rare", -10))
				local container = Instance.new("Folder")
				local holder = Instance.new("Folder")
				local ok, err = pcall(function()
					ItemView.reconcile(container, items, ClientConfig.assetStyles, assets, {
						rarities = rarities,
						rarityStyles = ClientConfig.rarityStyles,
					})
					local counts: { [string]: number } = { Highlight = 0, PointLight = 0, Sparkles = 0 }
					for _, descendant in container:GetDescendants() do
						if counts[descendant.ClassName] ~= nil then
							counts[descendant.ClassName] += 1
						end
					end
					local limits = ItemView.DEFAULT_LIMITS
					t.expect(counts).toEqual({
						Highlight = limits.highlights,
						PointLight = limits.lights,
						Sparkles = limits.sparkles,
					})
					local legendary = container:FindFirstChild("l1") :: Part
					t.expect({ legendary.Material, legendary.Size })
						.toEqual({ Enum.Material.Neon, Vector3.new(2.4, 2.4, 2.4) })
					local common = container:FindFirstChild("c1") :: Part
					t.expect({ common.Material, #common:GetChildren(), common:GetAttribute("base") })
						.toEqual({ Enum.Material.SmoothPlastic, 0, nil })
					local rare = container:FindFirstChild("r1") :: Part
					t.expect({ rare:FindFirstChildOfClass("PointLight"), rare:GetAttribute("rarity") })
						.toEqual({ nil, "rare" })

					local base = legendary:GetAttribute("base") :: Vector3
					ItemView.animate(container, 1.3)
					local lift = legendary.Position.Y - base.Y
					t.expect(lift >= -1e-6 and lift <= 0.45 + 1e-6).toBe(true)

					-- onRemove uebernimmt den Part (z. B. Sog-Animation), statt ihn zu zerstoeren.
					ItemView.reconcile(container, {}, ClientConfig.assetStyles, assets, {
						onRemove = function(part: BasePart): boolean
							if part.Name == "c1" then
								part.Parent = holder
								return true
							end
							return false
						end,
					})
					t.expect(#container:GetChildren()).toBe(0)
					t.expect(holder:FindFirstChild("c1") ~= nil).toBe(true)
				end)
				container:Destroy()
				holder:Destroy()
				if not ok then
					error(err, 0)
				end
			end
		)

		t.it("127 CollectFx: collected part flies to the character and is removed at the end", function()
			local world = Instance.new("Folder")
			world.Parent = workspace
			local ok, err = pcall(function()
				local now = 100
				local fx = CollectFx.new(world, {
					clock = function()
						return now
					end,
				})
				local root = Instance.new("Part")
				root.Anchored = true
				root.Position = Vector3.new(10, 0, 0)
				root.Parent = world
				local items = Instance.new("Folder")
				items.Parent = world
				local part = Instance.new("Part")
				part.Anchored = true
				part.Position = Vector3.new(0, 0, 0)
				part.Size = Vector3.new(2, 2, 2)
				part.Parent = items
				t.expect(fx:pull(part, nil)).toBe(false)
				t.expect(part.Parent).toBe(items)
				t.expect(fx:pull(part, root)).toBe(true)
				t.expect(part.Parent).toBe(world)
				t.expect(part:FindFirstChildOfClass("Beam") ~= nil).toBe(true)
				t.expect(fx:update(now + 0.2)).toBe(1)
				t.expect(part.Position.X > 0 and part.Position.X < 10).toBe(true)
				t.expect(part.Size.X < 2).toBe(true)
				t.expect(fx:update(now + CollectFx.DEFAULT_DURATION + 0.01)).toBe(0)
				t.expect(part.Parent).toBe(nil)
				local burst = root:FindFirstChild("FactoryCollectBurst")
				t.expect(burst ~= nil and burst:FindFirstChildOfClass("ParticleEmitter") ~= nil).toBe(true)
				t.expect(CollectFx.lerpPosition(Vector3.zero, Vector3.new(10, 0, 0), 0.5)).toBe(Vector3.new(2.5, 0, 0))
			end)
			world:Destroy()
			if not ok then
				error(err, 0)
			end
		end)

		t.it("128 LightingProfile.apply sets Lighting values and effects, reports bad names, restore resets", function()
			local Lighting = game:GetService("Lighting")
			local brightness = Lighting.Brightness
			local timeOfDay = Lighting.TimeOfDay
			local restore, errors = LightingProfile.apply({
				properties = { Brightness = 2.75, TimeOfDay = "10:30:00" },
				atmosphere = { Density = 0.3 },
				bloom = { Intensity = 0.5 },
			})
			local ok, err = pcall(function()
				t.expect(errors).toEqual({})
				t.expect({ Lighting.Brightness, Lighting.TimeOfDay }).toEqual({ 2.75, "10:30:00" })
				local atmosphere = Lighting:FindFirstChild("FactoryAtmosphere") :: Atmosphere
				t.expect(math.abs(atmosphere.Density - 0.3) < 1e-4).toBe(true)
				t.expect(Lighting:FindFirstChild("FactoryBloomEffect") ~= nil).toBe(true)
				t.expect(Lighting:FindFirstChild("FactorySky")).toBe(nil)
			end)
			restore()
			t.expect({ Lighting.Brightness, Lighting.TimeOfDay }).toEqual({ brightness, timeOfDay })
			t.expect(Lighting:FindFirstChild("FactoryAtmosphere")).toBe(nil)
			if not ok then
				error(err, 0)
			end

			-- Das Testbed-Profil hat nur gueltige Eigenschaften; unbekannte Namen werden gemeldet.
			local restoreTestbed, testbedErrors = LightingProfile.apply(ClientConfig.lighting)
			restoreTestbed()
			t.expect(testbedErrors).toEqual({})
			local restoreBad, badErrors = LightingProfile.apply({ properties = { NoSuchProperty = 1 } })
			restoreBad()
			t.expect(#badErrors).toBe(1)
			t.expect(Lighting.Brightness).toBe(brightness)
		end)

		t.it(
			"132 ItemView composite shape: invisible anchor, welded visual parts, highlight on the whole shape",
			function()
				local container = Instance.new("Folder")
				local ok, err = pcall(function()
					local style = {
						size = 2,
						height = 1.6,
						color = Color3.fromRGB(200, 60, 40),
						parts = {
							{ "Block", 2, 1, 2, 0, 0.5, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, "#E0702E", "Metal" },
							{ "Cylinder", 0.6, 1, 1, 0, 1.3, 0, 0, -1, 0, 1, 0, 0, 0, 0, 1, "#2BF5E3", "Neon" },
						},
					}
					local shape = {
						instanceId = "c1",
						itemTypeId = "shape_item",
						zoneId = "zone_a",
						position = Vector3.new(0, 1, 0),
					}
					ItemView.reconcile(container, { shape }, { shape_asset = style }, { shape_item = "shape_asset" }, {
						rarities = { shape_item = "rare" },
					})
					local anchor = container:FindFirstChild("c1") :: Part
					local scale = ItemView.DEFAULT_RARITY_STYLES.rare.scale :: number
					t.expect({ anchor.Transparency, anchor.Anchored }).toEqual({ 1, true })
					t.expect(math.abs(anchor.Position.Y - (1 + 1.6 * scale / 2)) < 1e-3).toBe(true)
					local visual = anchor:FindFirstChild("Visual") :: Model
					local pieces = visual:GetChildren()
					t.expect(#pieces).toBe(2)
					local first = visual:FindFirstChild("P1") :: Part
					local second = visual:FindFirstChild("P2") :: Part
					t.expect({ first.Material, second.Material, second.Shape }).toEqual({
						Enum.Material.Metal,
						Enum.Material.Neon,
						Enum.PartType.Cylinder,
					})
					t.expect(math.abs(first.Size.X - 2 * scale) < 1e-3).toBe(true)
					for _, piece in pieces do
						local weld = piece:FindFirstChildOfClass("WeldConstraint") :: WeldConstraint
						t.expect({ piece.Name, (piece :: Part).Anchored, weld.Part0 })
							.toEqual({ piece.Name, false, anchor })
					end
					local highlight = anchor:FindFirstChildOfClass("Highlight") :: Highlight
					t.expect(highlight.Adornee).toBe(visual)
					ItemView.reconcile(container, {}, { shape_asset = style }, { shape_item = "shape_asset" })
					t.expect(#container:GetChildren()).toBe(0)
				end)
				container:Destroy()
				if not ok then
					error(err, 0)
				end
			end
		)
	end)
end
