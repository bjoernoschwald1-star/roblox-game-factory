--!strict
-- Tests 77-86: ServerRuntime mit Fake-Adaptern (Spieler, Charakter, Remotes, Welt, Analytics, Scheduler,
-- Lifecycle) und dem echten MarketAdapter ueber einem Fake-MarketplaceService. Speicher: MemoryAdapter.
local ServerScriptService = game:GetService("ServerScriptService")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local ServerRuntime = require(FactoryCore.server.Engine.ServerRuntime)
local PlayersAdapter = require(FactoryCore.server.Engine.PlayersAdapter)
local MarketAdapter = require(FactoryCore.server.Engine.MarketAdapter)
local Scheduler = require(FactoryCore.server.Engine.Scheduler)
local SampleConfig = require(ServerScriptService.FactoryCoreTests.fixtures.SampleConfig)

type Signal = {
	Connect: (self: any, fn: (...any) -> ()) -> any,
	Fire: (self: any, ...any) -> (),
}

local function fakeSignal(): Signal
	local handlers: { (...any) -> () } = {}
	return {
		Connect = function(_self, fn: (...any) -> ())
			table.insert(handlers, fn)
			return {
				Disconnect = function()
					local index = table.find(handlers, fn)
					if index ~= nil then
						table.remove(handlers, index)
					end
				end,
			}
		end,
		Fire = function(_self, ...: any)
			for _, fn in table.clone(handlers) do
				fn(...)
			end
		end,
	}
end

local function fakePlayer(userId: number, launchData: string?): any
	local player = { UserId = userId, launchData = launchData, kickedWith = nil :: string? }
	function player.GetJoinData(self: any)
		return { LaunchData = self.launchData }
	end
	function player.Kick(self: any, message: string)
		self.kickedWith = message
	end
	return player
end

type Env = {
	memory: MemoryAdapter.MemoryAdapter,
	delay: number,
	now: number,
	sent: { { name: string, fields: { [string]: any } } },
	positions: { [number]: Vector3 },
	owned: { [number]: boolean },
	ownsCalls: number,
	present: { any },
	added: Signal,
	removing: Signal,
	remoteHandlers: { [string]: (player: any, ...any) -> () },
	market: { [string]: any },
	missingWorld: { string },
	closeHandler: (() -> ())?,
	scheduler: Scheduler.FakeScheduler,
}

local function newEnv(): Env
	local env = {} :: Env
	env.memory = MemoryAdapter.new()
	env.delay = 0
	env.now = 1000
	env.sent = {}
	env.positions = {}
	env.owned = {}
	env.ownsCalls = 0
	env.present = {}
	env.added = fakeSignal()
	env.removing = fakeSignal()
	env.remoteHandlers = {}
	env.missingWorld = {}
	env.scheduler = Scheduler.fake()
	env.market = {
		PromptGamePassPurchaseFinished = fakeSignal(),
		PromptProductPurchaseFinished = fakeSignal(),
		UserOwnsGamePassAsync = function(_self, _userId: number, passId: number): boolean
			env.ownsCalls += 1
			return env.owned[passId] == true
		end,
	}
	return env
end

local function start(env: Env, overrides: { [string]: any }?): ServerRuntime.Runtime
	local storage = {
		read = function(_self, key: string)
			return env.memory:read(key)
		end,
		update = function(_self, key: string, transform)
			if env.delay > 0 then
				task.wait(env.delay)
			end
			return env.memory:update(key, transform)
		end,
		remove = function(_self, key: string)
			return env.memory:remove(key)
		end,
	}
	local options: { [string]: any } = {
		adapters = {
			players = {
				onAdded = function(_self, callback)
					return env.added:Connect(callback)
				end,
				onRemoving = function(_self, callback)
					return env.removing:Connect(callback)
				end,
				getPlayers = function()
					return env.present
				end,
				kick = function(_self, player, message)
					player:Kick(message)
				end,
				joinSource = function(_self, player)
					return PlayersAdapter.joinSourceOf(player)
				end,
			},
			character = {
				position = function(_self, player): Vector3?
					return env.positions[player.UserId]
				end,
			},
			remotes = {
				bind = function(_self, name: string, handler)
					env.remoteHandlers[name] = handler
					return { Disconnect = function() end }
				end,
			},
			world = {
				validateWorld = function(): { string }
					return env.missingWorld
				end,
				spawnPosition = function(): Vector3
					return Vector3.new(1, 0, 0)
				end,
				isInSellArea = function(_self, position: Vector3): boolean
					return position.X >= 50
				end,
			},
			market = MarketAdapter.new(env.market),
			analytics = {
				sink = function(name: string, fields)
					table.insert(env.sent, { name = name, fields = fields })
				end,
			},
			scheduler = env.scheduler,
			lifecycle = {
				bindToClose = function(_self, handler: () -> ())
					env.closeHandler = handler
				end,
			},
		},
		storage = storage,
		keyPrefix = "profile_",
		serverId = "server-a",
		clock = function()
			return env.now
		end,
		sleep = function() end,
		rng = Random.new(31),
	}
	local config: any = SampleConfig()
	for name, value in overrides or {} do
		if name == "config" then
			config = value
		else
			options[name] = value
		end
	end
	return ServerRuntime.start(config, options :: any)
end

local function sentFor(env: Env, name: string, userId: number): { { [string]: any } }
	local list = {}
	for _, event in env.sent do
		if event.name == name and event.fields.userId == userId then
			table.insert(list, event.fields)
		end
	end
	return list
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("server runtime", function()
		t.it("77 join registers players (also those present at start) with startCoins and session source", function()
			local env = newEnv()
			local early = fakePlayer(101, '{"source":"organic"}')
			env.present = { early }
			local runtime = start(env)
			local modules = runtime.game.modules

			t.expect(modules.economy:balance({ userId = 101 })).toBe(20)
			t.expect(sentFor(env, "session_start", 101)[1].source).toBe("organic")

			env.added:Fire(fakePlayer(102, "paid"))
			t.expect(modules.economy:balance({ userId = 102 })).toBe(20)
			t.expect(sentFor(env, "session_start", 102)[1].source).toBe("paid")
			-- Ein erneutes PlayerAdded fuer einen bereits angemeldeten Spieler wird ignoriert.
			env.added:Fire(early)
			t.expect(#sentFor(env, "session_start", 101)).toBe(1)
			runtime:stop()
		end)

		t.it("78 remote collect uses the server-side character position; no character means nothing happens", function()
			local env = newEnv()
			local runtime = start(env)
			local player = fakePlayer(101)
			env.added:Fire(player)
			local inventory = runtime.game.modules.inventory

			local ok = pcall(env.remoteHandlers.collect, player)
			t.expect(ok).toBe(true)
			t.expect(inventory:count({ userId = 101 })).toBe(0)

			env.positions[101] = Vector3.new(0, 0, 0)
			env.remoteHandlers.collect(player)
			t.expect(inventory:count({ userId = 101 })).toBe(8)
			t.expect(#sentFor(env, "first_collect", 101)).toBe(1)
			runtime:stop()
		end)

		t.it("79 sell only inside a sell area: outside nothing happens, inside coins are credited", function()
			local env = newEnv()
			local runtime = start(env)
			local player = fakePlayer(101)
			env.added:Fire(player)
			local modules = runtime.game.modules
			local ctx = { userId = 101 }
			env.positions[101] = Vector3.new(0, 0, 0)
			env.remoteHandlers.collect(player)

			env.remoteHandlers.sell(player)
			t.expect(modules.inventory:count(ctx)).toBe(8)
			t.expect(modules.economy:balance(ctx)).toBe(20)

			env.positions[101] = Vector3.new(60, 0, 0)
			env.remoteHandlers.sell(player)
			t.expect(modules.inventory:count(ctx)).toBe(0)
			t.expect((modules.economy:balance(ctx) :: number) > 20).toBe(true)
			runtime:stop()
		end)

		t.it("80 leaving releases the profile; coming back loads the state", function()
			local env = newEnv()
			local runtime = start(env)
			local player = fakePlayer(101)
			env.added:Fire(player)
			runtime.game.modules.economy:credit({ userId = 101 }, 100, "test_reward")

			env.removing:Fire(player)
			t.expect(env.memory:peek("profile_101").session).toBe(nil)
			t.expect(env.memory:peek("profile_101").coins).toBe(120)
			t.expect(runtime.game.modules.session:get({ userId = 101 })).toBe(nil)
			t.expect(#sentFor(env, "session_end", 101)).toBe(1)

			env.added:Fire(player)
			t.expect(runtime.game.modules.economy:balance({ userId = 101 })).toBe(120)
			runtime:stop()
		end)

		t.it("81 load failed (foreign lock): kicked with loadFailedMessage, not registered", function()
			local env = newEnv()
			env.memory:seed("profile_101", {
				schemaVersion = 1,
				coins = 5,
				session = { serverId = "server-x", timestamp = env.now },
			})
			local runtime = start(env, { loadFailedMessage = "load_failed_test" })
			local player = fakePlayer(101)
			env.added:Fire(player)

			t.expect(player.kickedWith).toBe("load_failed_test")
			t.expect(runtime.game.modules.session:get({ userId = 101 })).toBe(nil)
			t.expect(#sentFor(env, "session_start", 101)).toBe(0)
			env.positions[101] = Vector3.new(0, 0, 0)
			env.remoteHandlers.collect(player)
			t.expect(env.memory:peek("profile_101").coins).toBe(5)
			runtime:stop()
		end)

		t.it(
			"82 receipt handler returns real Enum.ProductPurchaseDecision values; product prompt -> attempt",
			function()
				local env = newEnv()
				local runtime = start(env)
				env.added:Fire(fakePlayer(101))
				local process = env.market.ProcessReceipt

				t.expect(process({ PurchaseId = "r1", PlayerId = 101, ProductId = 1 }))
					.toBe(Enum.ProductPurchaseDecision.PurchaseGranted)
				t.expect(runtime.game.modules.economy:balance({ userId = 101 })).toBe(520)
				t.expect(process({ PurchaseId = "r2", PlayerId = 999, ProductId = 1 }))
					.toBe(Enum.ProductPurchaseDecision.NotProcessedYet)

				env.market.PromptProductPurchaseFinished:Fire(101, 2, false)
				env.market.PromptProductPurchaseFinished:Fire(101, 424242, true)
				local attempts = sentFor(env, "purchase_attempt", 101)
				t.expect(#attempts).toBe(1)
				t.expect({ attempts[1].role, attempts[1].accepted }).toEqual({ "bundle_vip", false })
				t.expect(runtime.game.modules.economy:balance({ userId = 101 })).toBe(520)

				runtime:stop()
				t.expect(env.market.ProcessReceipt).toBe(nil)
			end
		)

		t.it("83 pass prompt: effect only after a confirmed ownership check", function()
			local env = newEnv()
			local runtime = start(env)
			local player = fakePlayer(101)
			env.added:Fire(player)
			local modifiers = runtime.game.modules.modifiers
			local ctx = { userId = 101 }
			local callsAfterJoin = env.ownsCalls

			env.market.PromptGamePassPurchaseFinished:Fire(player, 1, false)
			t.expect(env.ownsCalls).toBe(callsAfterJoin)
			t.expect(modifiers:value(ctx, "range")).toBe(10)

			env.market.PromptGamePassPurchaseFinished:Fire(player, 1, true)
			t.expect(env.ownsCalls).toBe(callsAfterJoin + 1)
			t.expect(modifiers:value(ctx, "range")).toBe(10)

			env.owned[1] = true
			env.market.PromptGamePassPurchaseFinished:Fire(player, 1, true)
			t.expect(modifiers:value(ctx, "range")).toBe(20)
			runtime:stop()
		end)

		t.it("84 shutdown releases all profiles in parallel within the budget", function()
			local env = newEnv()
			local runtime = start(env)
			for userId = 201, 205 do
				env.added:Fire(fakePlayer(userId))
			end
			env.delay = 0.3

			local startedAt = os.clock()
			local handler = env.closeHandler :: () -> ()
			handler()
			local elapsed = os.clock() - startedAt
			for userId = 201, 205 do
				local key = "profile_" .. userId
				t.expect({ key, env.memory:peek(key).session }).toEqual({ key })
				t.expect({ key, #sentFor(env, "session_end", userId) }).toEqual({ key, 1 })
			end
			t.expect({ "elapsed", elapsed < 1.0 }).toEqual({ "elapsed", true })
			print(string.format("[spike] SHUTDOWN 5 players released in %.2fs (sequential would be >= 1.5s)", elapsed))
			runtime:stop()
		end)

		t.it("85 fake scheduler: autosave after autosaveSeconds, refill after respawn time", function()
			local env = newEnv()
			local runtime = start(env)
			local player = fakePlayer(101)
			env.added:Fire(player)
			local modules = runtime.game.modules
			local ctx = { userId = 101 }

			modules.economy:credit(ctx, 77, "test_reward")
			env.scheduler:advance(59)
			t.expect(env.memory:peek("profile_101").coins).toBe(20)
			env.scheduler:advance(1)
			t.expect(env.memory:peek("profile_101").coins).toBe(97)

			env.positions[101] = Vector3.new(0, 0, 0)
			env.remoteHandlers.collect(player)
			t.expect(#(modules.collecting:instances(ctx) :: { any })).toBe(0)
			env.now += 4
			env.scheduler:advance(1)
			t.expect(#(modules.collecting:instances(ctx) :: { any })).toBe(8)
			runtime:stop()
		end)

		t.it("86 start errors: sell.trigger npc and a missing zone part are named clearly", function()
			local env = newEnv()
			local config: any = SampleConfig()
			config.sell.trigger = "npc"
			local npcOk, npcErr = pcall(start, env, { config = config })
			t.expect(npcOk).toBe(false)
			t.expect(string.find(tostring(npcErr), '"npc"', 1, true) ~= nil).toBe(true)

			env.missingWorld = { "FactoryWorld.Zones.zone_c" }
			local worldOk, worldErr = pcall(start, env)
			t.expect(worldOk).toBe(false)
			t.expect(string.find(tostring(worldErr), "FactoryWorld.Zones.zone_c", 1, true) ~= nil).toBe(true)
		end)
	end)
end
