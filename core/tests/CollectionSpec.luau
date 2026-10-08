--!strict
-- Tests 143-148: Sammelalbum (Collection) ueber GameServer mit der SampleConfig plus collection- und
-- prestige-Abschnitt; dazu Validator, Simulator und Schnappschuss.
local ServerScriptService = game:GetService("ServerScriptService")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local GameServer = require(FactoryCore.server.GameServer)
local Simulator = require(FactoryCore.server.Config.Simulator)
local Validator = require(FactoryCore.server.Config.Validator)
local SampleConfig = require(ServerScriptService.FactoryCoreTests.fixtures.SampleConfig)

local A = { userId = 101 }

type Env = {
	memory: MemoryAdapter.MemoryAdapter,
	now: number,
	snapshots: { any },
}

local function config(): any
	local value: any = SampleConfig()
	value.collection = {
		groups = {
			group_a = {
				order = 1,
				nameKey = "zone_a_name",
				entries = {
					{ id = "small", itemTypes = { "item_small" } },
					{ id = "medium", itemTypes = { "item_medium" } },
				},
				reward = { coins = 100, effects = { sellFactor = { mul = 1.1 } } },
			},
			group_b = {
				order = 2,
				nameKey = "zone_b_name",
				entries = {
					{ id = "large", itemTypes = { "item_large" } },
					{ id = "rare", itemTypes = { "item_rare" } },
				},
				reward = { coins = 50 },
			},
		},
	}
	value.prestige = { coinsRequired = 500, sellBonusPerLevel = 0.5 }
	return value
end

local function newEnv(): Env
	return { memory = MemoryAdapter.new(), now = 1000, snapshots = {} }
end

local function compose(env: Env, serverId: string?, source: any?): GameServer.Game
	return GameServer.compose(source or config(), {
		storage = env.memory,
		dataStoreKeyPrefix = "profile_",
		serverId = serverId or "server-a",
		clock = function()
			return env.now
		end,
		sleep = function() end,
		rng = Random.new(3),
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

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("collection", function()
		t.it("143 new entry is recorded once; duplicates, repeats and unknown item types are ignored", function()
			local app = compose(newEnv())
			app:playerJoined(A, "organic")
			local collection = app.modules.collection :: any
			local first = collection:record(A, { "item_small", "item_small", "item_unknown" })
			t.expect({ first.newEntries, first.completedGroups, first.err }).toEqual({ { "small" }, {}, nil })
			t.expect(collection:record(A, { "item_small" }).newEntries).toEqual({})
			local state = collection:state(A)
			t.expect({ state.foundCount, state.total, state.found }).toEqual({ 1, 4, { small = true } })
			t.expect({ state.groups.group_a.found, state.groups.group_a.done }).toEqual({ 1, false })
		end)

		t.it("144 group complete: coins and bonus exactly once, saved at once; later records give nothing", function()
			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			local modules = app.modules
			local collection = modules.collection :: any
			collection:record(A, { "item_small" })
			local done = collection:record(A, { "item_medium" })
			t.expect({ done.newEntries, done.completedGroups }).toEqual({ { "medium" }, { "group_a" } })
			t.expect(modules.economy:balance(A)).toBe(120)
			t.expect(modules.modifiers:value(A, "sellFactor")).toBe(1.1)
			t.expect(env.memory:peek("profile_101").collection.rewarded).toEqual({ group_a = true })
			t.expect(collection:record(A, { "item_small", "item_medium" }).completedGroups).toEqual({})
			t.expect(modules.economy:balance(A)).toBe(120)
			modules.inventory:add(A, "item_medium", 4)
			t.expect(modules.selling:sell(A).earned).toBe(22)
		end)

		t.it("145 collect via dispatch records found types; album and bonus survive a prestige reset", function()
			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic")
			local modules = app.modules
			local collection = modules.collection :: any
			t.expect({ app:dispatch(A, "collect") }).toEqual({ true })
			local state = collection:state(A)
			t.expect(state.foundCount >= 1).toBe(true)
			for entryId in state.found do
				t.expect(entryId == "small" or entryId == "medium").toBe(true)
			end
			collection:record(A, { "item_small", "item_medium" })
			modules.economy:credit(A, 1000, "test_reward")
			env.now += 5
			t.expect({ app:dispatch(A, "prestige") }).toEqual({ true })
			t.expect((modules.prestige :: any):level(A)).toBe(1)
			t.expect(collection:state(A).found).toEqual({ small = true, medium = true })
			t.expect(collection:state(A).groups.group_a.done).toBe(true)
			t.expect(modules.modifiers:value(A, "sellFactor")).toBe(1.1 * 1.5)
		end)

		t.it("146 save and load: found entries, rewarded groups and bonus survive a server change", function()
			local env = newEnv()
			local first = compose(env, "server-a")
			first:playerJoined(A, "organic")
			local collection = first.modules.collection :: any
			collection:record(A, { "item_small", "item_medium", "item_large" })
			t.expect({ first:playerLeaving(A) }).toEqual({ true })
			local second = compose(env, "server-b")
			t.expect(second:playerJoined(A, "organic").state).toBe("LOADED")
			local state = (second.modules.collection :: any):state(A)
			t.expect(state.found).toEqual({ small = true, medium = true, large = true })
			t.expect({ state.groups.group_a.done, state.groups.group_b.done }).toEqual({ true, false })
			t.expect(second.modules.modifiers:value(A, "sellFactor")).toBe(1.1)
			-- Keine zweite Belohnung nach dem Laden.
			t.expect((second.modules.collection :: any):record(A, { "item_small" }).completedGroups).toEqual({})
		end)

		t.it(
			"147 old profile without field gets an empty album; a corrupt value gives CORRUPT_VALUE, unchanged",
			function()
				local env = newEnv()
				env.memory:seed("profile_101", {
					schemaVersion = 1,
					coins = 5,
					inventory = {},
					upgrades = {},
					zones = {},
					purchases = {},
					perks = {},
					funnel = {},
				})
				local corrupt = { found = { small = "yes" }, rewarded = {} }
				env.memory:seed("profile_202", { schemaVersion = 1, coins = 5, collection = corrupt })
				local app = compose(env)
				t.expect(app:playerJoined(A, "organic").state).toBe("LOADED")
				local collection = app.modules.collection :: any
				t.expect(collection:state(A).foundCount).toBe(0)
				t.expect(app.modules.session:get(A).collection).toEqual({ found = {}, rewarded = {} })

				local B = { userId = 202 }
				app:playerJoined(B, "organic")
				t.expect(collection:state(B)).toBe(nil)
				local result = collection:record(B, { "item_small", "item_medium" })
				t.expect({ result.newEntries, result.completedGroups, result.err }).toEqual({ {}, {}, "CORRUPT_VALUE" })
				t.expect(app.modules.session:get(B).collection).toEqual(corrupt)
				t.expect({ app.modules.economy:balance(B), app.modules.modifiers:value(B, "sellFactor") })
					.toEqual({ 5, 1 })
			end
		)

		t.it("148 validator, simulator and snapshot know the album", function()
			local broken = config()
			broken.collection.groups.group_b.entries[1].itemTypes = { "item_small" }
			broken.collection.groups.group_b.entries[2].itemTypes = { "item_missing" }
			broken.collection.groups.group_b.reward.effects = { luck = { mul = 2 } }
			local paths = {}
			for _, problem in Validator.validate(broken).errors do
				table.insert(paths, problem.path .. ":" .. problem.code)
			end
			table.sort(paths)
			t.expect(paths).toEqual({
				"collection.groups.group_b.entries.1.itemTypes:DUPLICATE",
				"collection.groups.group_b.entries.2.itemTypes:UNKNOWN_REFERENCE",
				"collection.groups.group_b.reward.effects.luck:UNKNOWN_ENUM",
			})

			local late = config()
			late.prestige.coinsRequired = 5000
			local without = config()
			without.prestige.coinsRequired = 5000
			without.collection = nil
			local options = { maxMinutes = 600, buyPolicy = "cheapest_first", goal = "prestige" } :: any
			local withAlbum = Simulator.run(late, options).minutesToFirstPrestige :: number
			local plain = Simulator.run(without, options).minutesToFirstPrestige :: number
			t.expect(withAlbum <= plain).toBe(true)

			local env = newEnv()
			local app = compose(env)
			app:playerJoined(A, "organic");
			(app.modules.collection :: any):record(A, { "item_small", "item_medium" })
			app:flushState()
			local snapshot = env.snapshots[#env.snapshots]
			t.expect({ snapshot.collection.foundCount, snapshot.collection.total }).toEqual({ 2, 4 })
			t.expect(snapshot.collection.groups.group_a).toEqual({
				order = 1,
				entries = { "small", "medium" },
				found = 2,
				done = true,
				rewardCoins = 100,
				rewardEffects = { sellFactor = { mul = 1.1 } },
			})
		end)
	end)
end
