--!strict
-- Tests 135-141: Prestige (Zuruecksetzen gegen dauerhaften Verkaufsmultiplikator) ueber GameServer und Remote,
-- mit der SampleConfig plus prestige-Abschnitt; dazu Validator, Simulator-Ziele und Schnappschuss.
local ServerScriptService = game:GetService("ServerScriptService")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local GameServer = require(FactoryCore.server.GameServer)
local Simulator = require(FactoryCore.server.Config.Simulator)
local Validator = require(FactoryCore.server.Config.Validator)
local SampleConfig = require(ServerScriptService.FactoryCoreTests.fixtures.SampleConfig)

local A = { userId = 101 }
local REQUIRED = 500

type Env = {
	memory: MemoryAdapter.MemoryAdapter,
	now: number,
	snapshots: { any },
}

local function config(): any
	local value: any = SampleConfig()
	value.prestige = { coinsRequired = REQUIRED, sellBonusPerLevel = 0.5 }
	return value
end

local function compose(env: Env, serverId: string?): GameServer.Game
	return GameServer.compose(config(), {
		storage = env.memory,
		dataStoreKeyPrefix = "profile_",
		serverId = serverId or "server-a",
		clock = function()
			return env.now
		end,
		sleep = function() end,
		rng = Random.new(5),
		spawnPosition = function(): Vector3
			return Vector3.new(1, 0, 0)
		end,
		getPosition = function(): Vector3?
			return Vector3.new(0, 0, 0)
		end,
		canSell = function()
			return true
		end,
		ownsPass = function()
			return false
		end,
		analyticsSink = function() end,
		onLoadFailed = function() end,
		sendState = function(_ctx, snapshot)
			table.insert(env.snapshots, snapshot)
		end,
	})
end

local function newEnv(): Env
	return { memory = MemoryAdapter.new(), now = 1000, snapshots = {} }
end

-- Bringt A auf Zone 2, Upgrade range 1 und genau `coins` Coins.
local function progress(app: GameServer.Game, coins: number)
	local modules = app.modules
	modules.economy:credit(A, 1000, "test_reward")
	modules.upgrades:purchase(A, "range")
	modules.zones:tryUnlock(A, "zone_b")
	local balance = modules.economy:balance(A) :: number
	if balance > coins then
		modules.economy:debit(A, balance - coins, "test_reward")
	elseif balance < coins then
		modules.economy:credit(A, coins - balance, "test_reward")
	end
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("prestige", function()
		t.it("135 below the threshold: remote accepted, nothing reset, canReset NOT_ENOUGH_COINS", function()
			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			progress(app, REQUIRED - 1)
			local prestige = app.modules.prestige :: any
			t.expect({ prestige:canReset(A) }).toEqual({ false, "NOT_ENOUGH_COINS" })
			t.expect({ app:dispatch(A, "prestige") }).toEqual({ true })
			t.expect(prestige:level(A)).toBe(0)
			t.expect(app.modules.economy:balance(A)).toBe(REQUIRED - 1)
			t.expect(app.modules.upgrades:level(A, "range")).toBe(1)
			t.expect(app.modules.zones:isUnlocked(A, "zone_b")).toBe(true)
			-- Zusatzargumente werden vom Gateway abgelehnt, ohne Handler.
			env.now += 5
			t.expect({ app:dispatch(A, "prestige", 99) }).toEqual({ false, "BAD_ARGS" })
		end)

		t.it(
			"136 successful reset: coins, upgrades and zones back to start, level 1, items respawned, saved",
			function()
				local env = newEnv()
				local app = compose(env)
				app:playerJoined(A, "organic")
				progress(app, REQUIRED + 40)
				app.modules.inventory:add(A, "item_small", 3)
				t.expect({ app:dispatch(A, "prestige") }).toEqual({ true })
				local modules = app.modules
				t.expect((modules.prestige :: any):level(A)).toBe(1)
				t.expect(modules.economy:balance(A)).toBe(20)
				t.expect(modules.upgrades:level(A, "range")).toBe(0)
				t.expect(modules.zones:isUnlocked(A, "zone_b")).toBe(false)
				t.expect(modules.zones:isUnlocked(A, "zone_a")).toBe(true)
				t.expect(modules.inventory:count(A)).toBe(3)
				for _, instance in modules.collecting:instances(A) :: { any } do
					t.expect(instance.zoneId).toBe("zone_a")
				end
				local stored = env.memory:peek("profile_101")
				t.expect({ stored.prestige, stored.coins, next(stored.upgrades) }).toEqual({ 1, 20, nil })
			end
		)

		t.it("137 multiplier acts on selling via Modifiers: level 1 -> x1.5, level 2 -> x2", function()
			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			local modules = app.modules
			modules.inventory:add(A, "item_medium", 4)
			t.expect(modules.selling:sell(A).earned).toBe(20)
			progress(app, REQUIRED)
			app:dispatch(A, "prestige")
			t.expect(modules.modifiers:value(A, "sellFactor")).toBe(1.5)
			modules.inventory:add(A, "item_medium", 4)
			t.expect(modules.selling:sell(A).earned).toBe(30)
			env.now += 5
			progress(app, REQUIRED)
			app:dispatch(A, "prestige")
			t.expect((modules.prestige :: any):multiplier(A)).toBe(2)
			modules.inventory:add(A, "item_medium", 4)
			t.expect(modules.selling:sell(A).earned).toBe(40)
		end)

		t.it("138 save and load: level and multiplier survive leaving and joining on another server", function()
			local env = newEnv()
			local first = compose(env, "server-a")
			first:playerJoined(A, "organic")
			progress(first, REQUIRED)
			first:dispatch(A, "prestige")
			t.expect({ first:playerLeaving(A) }).toEqual({ true })
			local second = compose(env, "server-b")
			t.expect(second:playerJoined(A, "organic").state).toBe("LOADED")
			t.expect((second.modules.prestige :: any):level(A)).toBe(1)
			t.expect(second.modules.modifiers:value(A, "sellFactor")).toBe(1.5)
		end)

		t.it("139 old profile without prestige field loads at level 0; corrupt value is not touched", function()
			local env = newEnv()
			env.memory:seed("profile_101", {
				schemaVersion = 1,
				coins = 700,
				inventory = {},
				upgrades = { range = 1 },
				zones = {},
				purchases = {},
				perks = {},
				funnel = {},
			})
			local app = compose(env)
			t.expect(app:playerJoined(A, "organic").state).toBe("LOADED")
			local prestige = app.modules.prestige :: any
			t.expect(prestige:level(A)).toBe(0)
			t.expect(app.modules.session:get(A).prestige).toBe(0)
			t.expect(app.modules.modifiers:value(A, "sellFactor")).toBe(1)
			app:dispatch(A, "prestige")
			t.expect(prestige:level(A)).toBe(1)

			local B = { userId = 202 }
			env.memory:seed("profile_202", { schemaVersion = 1, coins = 900, prestige = "x" })
			app:playerJoined(B, "organic")
			t.expect(prestige:level(B)).toBe(nil)
			t.expect({ prestige:canReset(B) }).toEqual({ false, "CORRUPT_VALUE" })
			app:dispatch(B, "prestige")
			t.expect({ app.modules.session:get(B).prestige, app.modules.economy:balance(B) }).toEqual({ "x", 900 })
		end)

		t.it("140 double request: second call rate limited, after the window below threshold; level stays 1", function()
			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			progress(app, REQUIRED * 3)
			t.expect({ app:dispatch(A, "prestige") }).toEqual({ true })
			t.expect({ app:dispatch(A, "prestige") }).toEqual({ false, "RATE_LIMITED" })
			env.now += 5
			t.expect({ app:dispatch(A, "prestige") }).toEqual({ true })
			t.expect((app.modules.prestige :: any):level(A)).toBe(1)
			t.expect(app.modules.economy:balance(A)).toBe(20)
		end)

		t.it("141 validator, simulator goals and snapshot know prestige", function()
			local broken = config()
			broken.prestige.coinsRequired = 0
			broken.prestige.sellBonusPerLevel = -1
			local result = Validator.validate(broken)
			local paths = {}
			for _, problem in result.errors do
				table.insert(paths, problem.path)
			end
			table.sort(paths)
			t.expect(paths).toEqual({ "prestige.coinsRequired", "prestige.sellBonusPerLevel" })
			local missingRemote: any = config()
			missingRemote.remotes.prestige = nil
			t.expect(Validator.validate(missingRemote).errors[1].code).toBe("MISSING_REMOTE")

			-- Hohe Schwelle, damit die erste Prestige-Moeglichkeit nach allen Zonen liegt.
			local late = config()
			late.prestige.coinsRequired = 5000
			local options = { maxMinutes = 600, buyPolicy = "cheapest_first", goal = "prestige" }
			local report = Simulator.run(late, options :: any)
			local allUpgrades = report.minutesToAllUpgrades :: number
			local first = report.minutesToFirstPrestige :: number
			t.expect(report.reachedAllZones).toBe(true)
			t.expect(first >= (report.minutesToZone[3] :: number)).toBe(true)
			t.expect(allUpgrades > 0).toBe(true)
			local upgradesOnly =
				Simulator.run(late, { maxMinutes = 600, buyPolicy = "cheapest_first", goal = "upgrades" } :: any)
			t.expect(upgradesOnly.minutesToAllUpgrades).toBe(allUpgrades)

			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			progress(app, REQUIRED)
			app:flushState()
			local snapshot = env.snapshots[#env.snapshots]
			t.expect(snapshot.prestige).toEqual({
				level = 0,
				multiplier = 1,
				nextMultiplier = 1.5,
				coinsRequired = REQUIRED,
				available = true,
			})
		end)
	end)
end
