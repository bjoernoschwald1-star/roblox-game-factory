--!strict
-- Tests 67-73: das Game aus Config + injizierten Diensten, bedient nur ueber playerJoined, dispatch usw.
local ServerScriptService = game:GetService("ServerScriptService")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local GameServer = require(FactoryCore.server.GameServer)
local SampleConfig = require(ServerScriptService.FactoryCoreTests.fixtures.SampleConfig)

local A = { userId = 101 }
local B = { userId = 202 }
local FUNNEL =
	{ session_start = true, first_collect = true, first_sell = true, first_upgrade = true, zone_unlock = true }

type Sent = { name: string, fields: { [string]: any } }

type Env = {
	memory: MemoryAdapter.MemoryAdapter,
	now: number,
	sent: { Sent },
	loadFailures: { { any } },
	owned: { [number]: boolean },
	noPosition: boolean,
}

local function newEnv(): Env
	local env = {} :: Env
	env.memory = MemoryAdapter.new()
	env.now = 1000
	env.sent = {}
	env.loadFailures = {}
	env.owned = {}
	env.noPosition = false
	return env
end

local function services(env: Env, serverId: string): GameServer.Services
	return {
		storage = env.memory,
		dataStoreKeyPrefix = "profile_",
		serverId = serverId,
		clock = function()
			return env.now
		end,
		sleep = function() end,
		rng = Random.new(21),
		spawnPosition = function(): Vector3
			return Vector3.new(1, 0, 0)
		end,
		getPosition = function(): Vector3?
			return if env.noPosition then nil else Vector3.new(0, 0, 0)
		end,
		canSell = function()
			return true
		end,
		ownsPass = function(_userId: number, passId: number): boolean
			return env.owned[passId] == true
		end,
		analyticsSink = function(name: string, fields)
			table.insert(env.sent, { name = name, fields = fields })
		end,
		onLoadFailed = function(ctx, state)
			table.insert(env.loadFailures, { ctx.userId, state })
		end,
	}
end

local function compose(env: Env, serverId: string?): GameServer.Game
	return GameServer.compose(SampleConfig(), services(env, serverId or "server-a"))
end

local function count(env: Env, name: string): number
	local n = 0
	for _, event in env.sent do
		if event.name == name then
			n += 1
		end
	end
	return n
end

local function last(env: Env, name: string): Sent?
	for index = #env.sent, 1, -1 do
		if env.sent[index].name == name then
			return env.sent[index]
		end
	end
	return nil
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("game server", function()
		t.it("67 compose throws with all messages for an invalid config; SampleConfig yields all modules", function()
			local env = newEnv()
			local broken: any = SampleConfig()
			broken.game.id = nil
			broken.remotes.sell = nil
			local ok, err = pcall(GameServer.compose, broken, services(env, "server-a"))
			t.expect(ok).toBe(false)
			t.expect(string.find(tostring(err), "game.id", 1, true) ~= nil).toBe(true)
			t.expect(string.find(tostring(err), "remotes.sell", 1, true) ~= nil).toBe(true)

			local app = compose(env)
			local names = {}
			for name, module in app.modules do
				if module ~= nil then
					table.insert(names, name)
				end
			end
			table.sort(names)
			t.expect(names).toEqual({
				"analytics",
				"collecting",
				"economy",
				"gateway",
				"inventory",
				"modifiers",
				"monetization",
				"selling",
				"session",
				"store",
				"upgrades",
				"zones",
			})
		end)

		t.it(
			"68 playerJoined: profile with startCoins, spawner started, session_start; onLoadFailed when locked",
			function()
				local env = newEnv()
				local app = compose(env)
				t.expect(app:playerJoined(A, "paid").state).toBe("NEW")
				t.expect(app.modules.economy:balance(A)).toBe(20)
				t.expect(#(app.modules.collecting:instances(A) :: { any })).toBe(8)
				local start = last(env, "session_start") :: Sent
				t.expect(start.fields.source).toBe("paid")
				t.expect(start.fields.userId).toBe(101)

				env.memory:seed("profile_202", {
					schemaVersion = 1,
					coins = 0,
					session = { serverId = "server-x", timestamp = env.now },
				})
				t.expect(app:playerJoined(B, "organic").state).toBe("LOCKED")
				t.expect(env.loadFailures).toEqual({ { 202, "LOCKED" } })
				t.expect(app.modules.collecting:instances(B)).toBe(nil)
				t.expect(count(env, "session_start")).toBe(1)
			end
		)

		t.it("69 whole flow via dispatch only; funnel events in order with gameId and configVersion", function()
			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			local modules = app.modules

			t.expect({ app:dispatch(A, "collect") }).toEqual({ true })
			t.expect(modules.inventory:count(A)).toBe(8)
			t.expect({ app:dispatch(A, "sell") }).toEqual({ true })
			t.expect(modules.inventory:count(A)).toBe(0)
			t.expect((modules.economy:balance(A) :: number) > 20).toBe(true)

			modules.economy:credit(A, 1000, "test_reward")
			t.expect(modules.modifiers:value(A, "range")).toBe(10)
			t.expect({ app:dispatch(A, "buyUpgrade", "range") }).toEqual({ true })
			t.expect(modules.upgrades:level(A, "range")).toBe(1)
			t.expect(modules.modifiers:value(A, "range")).toBe(15)

			t.expect({ app:dispatch(A, "unlockZone", "zone_b") }).toEqual({ true })
			t.expect(modules.zones:isUnlocked(A, "zone_b")).toBe(true)

			local funnel = {}
			for _, event in env.sent do
				if FUNNEL[event.name] then
					table.insert(funnel, event.name)
					t.expect({ event.name, event.fields.gameId, event.fields.configVersion }).toEqual({
						event.name,
						"sample_game",
						"1.0.0",
					})
				end
			end
			t.expect(funnel).toEqual({ "session_start", "first_collect", "first_sell", "first_upgrade", "zone_unlock" })
			t.expect((last(env, "zone_unlock") :: Sent).fields.zoneIndex).toBe(2)
			t.expect((last(env, "zone_unlock") :: Sent).fields.funnelStep).toBe(5)
		end)

		t.it("70 remote abuse via compose: position argument, unknown dimension, flood are rejected", function()
			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			local modules = app.modules
			modules.economy:credit(A, 1000, "test_reward")

			local posOk, posErr = app:dispatch(A, "collect", Vector3.new(1, 0, 0))
			t.expect({ posOk, posErr }).toEqual({ false, "BAD_ARGS" })
			t.expect(modules.inventory:count(A)).toBe(0)
			local dimOk, dimErr = app:dispatch(A, "buyUpgrade", "teleport_speed")
			t.expect({ dimOk, dimErr }).toEqual({ false, "BAD_ARGS" })
			local priceOk, priceErr = app:dispatch(A, "buyUpgrade", "range", 0)
			t.expect({ priceOk, priceErr }).toEqual({ false, "BAD_ARGS" })

			for _ = 1, 5 do
				t.expect((app:dispatch(A, "unlockZone", "zone_c"))).toBe(true)
			end
			local floodOk, floodErr = app:dispatch(A, "unlockZone", "zone_c")
			t.expect({ floodOk, floodErr }).toEqual({ false, "RATE_LIMITED" })

			t.expect(modules.economy:balance(A)).toBe(1020)
			t.expect(modules.upgrades:level(A, "range")).toBe(0)
			t.expect(modules.zones:isUnlocked(A, "zone_c")).toBe(false)
			t.expect(modules.gateway:rejectedCount(A)).toBe(4)
		end)

		t.it("71 collect with a full inventory sends inventory_full; no position means nothing happens", function()
			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			local modules = app.modules

			app:dispatch(A, "collect")
			t.expect(count(env, "inventory_full")).toBe(0)
			env.now += 4
			app:refillAll()
			t.expect(#(modules.collecting:instances(A) :: { any })).toBe(8)
			app:dispatch(A, "collect")
			t.expect(modules.inventory:count(A)).toBe(10)
			t.expect(count(env, "inventory_full")).toBe(1)

			env.noPosition = true
			local sentBefore = #env.sent
			t.expect({ app:dispatch(A, "collect") }).toEqual({ true })
			t.expect(modules.inventory:count(A)).toBe(10)
			t.expect(#env.sent).toBe(sentBefore)
		end)

		t.it("72 processReceipt via the game object; pass effect visible in getRange after refreshPasses", function()
			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			local modules = app.modules

			t.expect(app:processReceipt({ PurchaseId = "r1", PlayerId = 101, ProductId = 1 })).toBe("PurchaseGranted")
			t.expect(modules.economy:balance(A)).toBe(520)
			t.expect((last(env, "purchase_success") :: Sent).fields.role).toBe("coins_small")

			t.expect(modules.modifiers:value(A, "range")).toBe(10)
			env.owned[1] = true
			modules.monetization:refreshPasses(A)
			t.expect(modules.modifiers:value(A, "range")).toBe(20)
		end)

		t.it("73 leave and rejoin on a second server: coins, upgrades, zones and funnel status kept", function()
			local env = newEnv()
			local serverA = compose(env, "server-a")
			serverA:playerJoined(A, "organic")
			serverA:dispatch(A, "collect")
			serverA:dispatch(A, "sell")
			serverA.modules.economy:credit(A, 1000, "test_reward")
			serverA:dispatch(A, "buyUpgrade", "capacity")
			serverA:dispatch(A, "unlockZone", "zone_b")
			local balance = serverA.modules.economy:balance(A)
			env.now += 90
			t.expect(serverA:playerLeaving(A)).toBe(true)
			t.expect((last(env, "session_end") :: Sent).fields.durationSeconds).toBe(90)

			local serverB = compose(env, "server-b")
			t.expect(serverB:playerJoined(A, "organic").state).toBe("LOADED")
			local modules = serverB.modules
			t.expect(modules.economy:balance(A)).toBe(balance)
			t.expect(modules.upgrades:level(A, "capacity")).toBe(1)
			t.expect(modules.zones:unlockedZones(A)).toEqual({ "zone_a", "zone_b" })
			t.expect(modules.inventory:count(A)).toBe(0)
			serverB:dispatch(A, "collect")
			t.expect((modules.inventory:count(A) :: number) > 0).toBe(true)
			t.expect(count(env, "first_collect")).toBe(1)
			t.expect(count(env, "first_sell")).toBe(1)
			t.expect(count(env, "first_upgrade")).toBe(1)
		end)
	end)
end
