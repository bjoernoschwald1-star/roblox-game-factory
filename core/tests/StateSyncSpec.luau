--!strict
-- Tests 93-98 und 100: Zustand zum Client (StateSync ueber GameServer und direkt, echter RemoteBinder.fireClient).
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local GameServer = require(FactoryCore.server.GameServer)
local StateSync = require(FactoryCore.server.StateSync)
local RemoteBinder = require(FactoryCore.server.Engine.RemoteBinder)
local Log = require(FactoryCore.shared.Log)
local SampleConfig = require(ServerScriptService.FactoryCoreTests.fixtures.SampleConfig)

local A = { userId = 101 }
local B = { userId = 202 }
local SNAPSHOT_KEYS =
	{ "capacity", "coins", "inventory", "inventoryCount", "items", "range", "sellFactor", "seq", "upgrades", "zones" }

type Sent = { userId: number, snapshot: { [string]: any } }

type Env = {
	memory: MemoryAdapter.MemoryAdapter,
	now: number,
	sent: { Sent },
	sendFails: boolean,
}

local function newEnv(): Env
	local env = {} :: Env
	env.memory = MemoryAdapter.new()
	env.now = 1000
	env.sent = {}
	env.sendFails = false
	return env
end

local function compose(env: Env, withState: boolean): GameServer.Game
	local services: { [string]: any } = {
		storage = env.memory,
		dataStoreKeyPrefix = "profile_",
		serverId = "server-a",
		clock = function()
			return env.now
		end,
		sleep = function() end,
		rng = Random.new(41),
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
		log = Log.new({ sink = function() end }),
	}
	if withState then
		services.sendState = function(ctx, snapshot)
			if env.sendFails then
				error("transport down")
			end
			table.insert(env.sent, { userId = ctx.userId, snapshot = snapshot })
		end
	end
	return GameServer.compose(SampleConfig(), services :: any)
end

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local function lastFor(env: Env, userId: number): { [string]: any }?
	for index = #env.sent, 1, -1 do
		if env.sent[index].userId == userId then
			return env.sent[index].snapshot
		end
	end
	return nil
end

local function countFor(env: Env, userId: number): number
	local n = 0
	for _, entry in env.sent do
		if entry.userId == userId then
			n += 1
		end
	end
	return n
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("state sync", function()
		t.it(
			"93 snapshot after join: startCoins, capacity, upgrades with nextCost, start zone, own items only",
			function()
				local env = newEnv()
				local app = compose(env, true)
				app:playerJoined(A, "organic")
				t.expect(app:flushState()).toBe(1)

				local snapshot = lastFor(env, 101) :: { [string]: any }
				t.expect(sortedKeys(snapshot)).toEqual(SNAPSHOT_KEYS)
				t.expect(snapshot.seq).toBe(1)
				t.expect(snapshot.coins).toBe(20)
				t.expect(snapshot.capacity).toBe(10)
				t.expect(snapshot.inventoryCount).toBe(0)
				t.expect(snapshot.inventory).toEqual({})
				t.expect({ snapshot.range, snapshot.sellFactor }).toEqual({ 10, 1 })
				t.expect(snapshot.upgrades).toEqual({
					range = { level = 0, maxLevel = 2, nextCost = 50 },
					capacity = { level = 0, maxLevel = 3, nextCost = 100 },
					sell_bonus = { level = 0, maxLevel = 2, nextCost = 250 },
				})
				t.expect(snapshot.zones).toEqual({
					zone_a = { unlocked = true, order = 1 },
					zone_b = { unlocked = false, order = 2 },
					zone_c = { unlocked = false, order = 3 },
				})
				t.expect(#snapshot.items).toBe(8)
				for _, item in snapshot.items do
					t.expect(sortedKeys(item)).toEqual({ "instanceId", "itemTypeId", "position", "zoneId" })
					t.expect(typeof(item.position)).toBe("Vector3")
					t.expect(item.zoneId).toBe("zone_a")
				end

				-- Groessenabschaetzung: JSON mit Positionen als drei Zahlen.
				local encodable = table.clone(snapshot)
				local items = {}
				for _, item in snapshot.items do
					local copy = table.clone(item)
					copy.position = { item.position.X, item.position.Y, item.position.Z }
					table.insert(items, copy)
				end
				encodable.items = items
				print(
					string.format(
						"[spike] SNAPSHOT bytes~%d items=%d",
						#HttpService:JSONEncode(encodable),
						#snapshot.items
					)
				)
			end
		)

		t.it("94 two players: every snapshot only contains the player's own items and values", function()
			local env = newEnv()
			local app = compose(env, true)
			app:playerJoined(A, "organic")
			app:playerJoined(B, "organic")
			app:flushState()
			app:dispatch(A, "collect")
			env.now += 0.2
			app:flushState()

			local snapshotA = lastFor(env, 101) :: { [string]: any }
			local snapshotB = lastFor(env, 202) :: { [string]: any }
			t.expect({ snapshotA.seq, snapshotA.inventoryCount, #snapshotA.items }).toEqual({ 2, 8, 0 })
			t.expect({ snapshotB.seq, snapshotB.inventoryCount, #snapshotB.items }).toEqual({ 1, 0, 8 })
			t.expect(snapshotB.items).toEqual(app.modules.collecting:instances(B))
			t.expect(countFor(env, 202)).toBe(1)
		end)

		t.it("95 collect and sell produce newer snapshots; a rejected dispatch produces none", function()
			local env = newEnv()
			local app = compose(env, true)
			app:playerJoined(A, "organic")
			app:flushState()

			app:dispatch(A, "collect")
			env.now += 0.2
			app:flushState()
			local afterCollect = lastFor(env, 101) :: { [string]: any }
			t.expect({ afterCollect.seq, afterCollect.inventoryCount }).toEqual({ 2, 8 })

			app:dispatch(A, "sell")
			env.now += 0.2
			app:flushState()
			local afterSell = lastFor(env, 101) :: { [string]: any }
			t.expect({ afterSell.seq, afterSell.inventoryCount }).toEqual({ 3, 0 })
			t.expect(afterSell.coins > 20).toBe(true)

			t.expect((app:dispatch(A, "collect", Vector3.new(1, 0, 0)))).toBe(false)
			env.now += 0.2
			t.expect(app:flushState()).toBe(0)
			t.expect(countFor(env, 101)).toBe(3)
		end)

		t.it("96 throttle: many markDirty -> at most one snapshot per minIntervalSeconds", function()
			local env = newEnv()
			local app = compose(env, false)
			app:playerJoined(A, "organic")
			local sync = StateSync.new({
				modules = app.modules,
				config = SampleConfig(),
				send = function(ctx, snapshot)
					table.insert(env.sent, { userId = ctx.userId, snapshot = snapshot :: any })
				end,
				clock = function()
					return env.now
				end,
			})

			for _ = 1, 10 do
				sync:markDirty(A)
			end
			t.expect(sync:flush()).toBe(1)
			sync:markDirty(A)
			t.expect(sync:flush()).toBe(0)
			env.now += 0.1
			t.expect(sync:flush()).toBe(0)
			env.now += 0.1
			t.expect(sync:flush()).toBe(1)
			t.expect({ env.sent[1].snapshot.seq, env.sent[2].snapshot.seq }).toEqual({ 1, 2 })
			t.expect(sync:flush()).toBe(0)
		end)

		t.it("97 failing send keeps the player dirty; profile not loaded gives no snapshot and no error", function()
			local env = newEnv()
			local app = compose(env, true)
			app:playerJoined(A, "organic")
			env.sendFails = true
			t.expect(app:flushState()).toBe(0)
			env.sendFails = false
			t.expect(app:flushState()).toBe(1)
			t.expect((lastFor(env, 101) :: { [string]: any }).seq).toBe(1)

			local sync = StateSync.new({
				modules = app.modules,
				config = SampleConfig(),
				send = function()
					error("must not be called")
				end,
				log = Log.new({ sink = function() end }),
			})
			sync:markDirty({ userId = 999 })
			local called, sent = pcall(sync.flush, sync)
			t.expect({ called, sent }).toEqual({ true, 0 })
		end)

		t.it("98 without sendState GameServer behaves as before; flushState exists and does nothing", function()
			local env = newEnv()
			local app = compose(env, false)
			app:playerJoined(A, "organic")
			t.expect({ app:dispatch(A, "collect") }).toEqual({ true })
			t.expect(app.modules.inventory:count(A)).toBe(8)
			t.expect(app:flushState()).toBe(0)
			t.expect(#env.sent).toBe(0)
		end)

		t.it("100 real RemoteBinder.fireClient creates RemoteEvent stateUpdate once in FactoryRemotes", function()
			t.expect(ReplicatedStorage:FindFirstChild(RemoteBinder.FOLDER_NAME)).toBe(nil)
			local ok, err = pcall(function()
				local binder = RemoteBinder.new()
				-- Ohne echten Spieler kann FireClient nicht zustellen; hier zaehlt nur das Remote.
				pcall(binder.fireClient, binder, RemoteBinder.STATE_REMOTE, nil, { seq = 1 })
				pcall(RemoteBinder.new().fireClient, binder, RemoteBinder.STATE_REMOTE, nil, { seq = 2 })
				local folder = ReplicatedStorage:FindFirstChild(RemoteBinder.FOLDER_NAME) :: Instance
				local children = folder:GetChildren()
				t.expect(#children).toBe(1)
				t.expect(children[1].Name).toBe("stateUpdate")
				t.expect(children[1]:IsA("RemoteEvent")).toBe(true)
			end)
			local folder = ReplicatedStorage:FindFirstChild(RemoteBinder.FOLDER_NAME)
			if folder ~= nil then
				folder:Destroy()
			end
			if not ok then
				error(err, 0)
			end
			t.expect(ReplicatedStorage:FindFirstChild(RemoteBinder.FOLDER_NAME)).toBe(nil)
		end)
	end)
end
