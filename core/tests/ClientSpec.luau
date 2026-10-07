--!strict
-- Tests 101-104: Client-Grundlage (ClientState, Intents), geladen aus ReplicatedStorage.FactoryClient.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local FactoryCore = ServerScriptService.FactoryCore
local FactoryClient = ReplicatedStorage.FactoryClient
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local GameServer = require(FactoryCore.server.GameServer)
local Log = require(FactoryCore.shared.Log)
local SampleConfig = require(ServerScriptService.FactoryCoreTests.fixtures.SampleConfig)
local ClientState = require(FactoryClient.ClientState)
local Intents = require(FactoryClient.Intents)

local A = { userId = 101 }

-- Liefert einen echten Schnappschuss des Servers (StateSync ueber GameServer) fuer einen frisch geladenen Spieler.
local function serverSnapshot(): any
	local captured: any = nil
	local app = GameServer.compose(SampleConfig(), {
		storage = MemoryAdapter.new(),
		dataStoreKeyPrefix = "profile_",
		serverId = "server-a",
		clock = function()
			return 1000
		end,
		sleep = function() end,
		rng = Random.new(51),
		spawnPosition = function(_zoneId: string, rng: Random): Vector3
			return Vector3.new(rng:NextNumber(-5, 5), 0.5, rng:NextNumber(-5, 5))
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
		sendState = function(_ctx, snapshot)
			captured = snapshot
		end,
	})
	app:playerJoined(A, "organic")
	app:flushState()
	return captured
end

local function withSeq(snapshot: any, seq: number, changes: { [string]: any }?): any
	local copy = table.clone(snapshot)
	copy.seq = seq
	for key, value in changes or {} do
		copy[key] = value
	end
	return copy
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("client", function()
		t.it("101 ClientState applies newer seq only, drops broken snapshots, onChanged only on acceptance", function()
			local base = serverSnapshot()
			local state = ClientState.new()
			local seen: { number } = {}
			local good = 0
			state:onChanged(function()
				error("listener bug")
			end)
			local disconnect = state:onChanged(function(snapshot)
				good += 1
				table.insert(seen, snapshot.seq)
			end)

			t.expect(state:get()).toBe(nil)
			t.expect(state:apply(withSeq(base, 1))).toBe(true)
			t.expect(state:apply(withSeq(base, 1))).toBe(false)
			t.expect(state:apply(withSeq(base, 0))).toBe(false)
			t.expect(state:apply({ seq = 5, coins = "x" })).toBe(false)
			t.expect(state:apply(withSeq(base, 6, { items = { { instanceId = "i1", position = { 1, 2, 3 } } } })))
				.toBe(false)
			t.expect(state:apply(nil)).toBe(false)
			t.expect(state:apply(withSeq(base, 3, { coins = 99 }))).toBe(true)
			t.expect((state:get() :: any).coins).toBe(99)
			t.expect(seen).toEqual({ 1, 3 })

			disconnect()
			t.expect(state:apply(withSeq(base, 4))).toBe(true)
			t.expect(good).toBe(2)
		end)

		t.it("102 ClientState helpers canAfford, isFull and nextZone from a SampleConfig snapshot", function()
			local base = serverSnapshot()
			local state = ClientState.new()
			t.expect({ state:isFull(), state:nextZone(), state:canAfford("range") }).toEqual({ false, nil, false })

			state:apply(withSeq(base, 1))
			t.expect(state:canAfford("range")).toBe(false) -- 20 Coins, naechste Stufe kostet 50
			t.expect(state:canAfford("unknown")).toBe(false)
			t.expect(state:isFull()).toBe(false)
			t.expect(state:nextZone()).toBe("zone_b")

			local maxed = table.clone(base.upgrades)
			maxed.range = { level = 2, maxLevel = 2 }
			state:apply(withSeq(base, 2, { coins = 100, inventoryCount = base.capacity, upgrades = maxed }))
			t.expect(state:canAfford("capacity")).toBe(true) -- 100 >= 100
			t.expect(state:canAfford("sell_bonus")).toBe(false) -- 100 < 250
			t.expect(state:canAfford("range")).toBe(false) -- Maximalstufe
			t.expect(state:isFull()).toBe(true)

			local zones = table.clone(base.zones)
			zones.zone_b = { unlocked = true, order = 2 }
			state:apply(withSeq(base, 3, { zones = zones }))
			t.expect(state:nextZone()).toBe("zone_c")
			zones.zone_c = { unlocked = true, order = 3 }
			state:apply(withSeq(base, 4, { zones = zones }))
			t.expect(state:nextZone()).toBe(nil)
		end)

		t.it("103 Intents fire the right names and arguments; collect spam is throttled; no values sent", function()
			local now = 0
			local fired: { { any } } = {}
			local intents = Intents.new({
				fire = function(name: string, ...: any)
					table.insert(fired, { name, ... })
				end,
				clock = function()
					return now
				end,
			})

			t.expect(intents:collect()).toBe(true)
			t.expect(intents:collect()).toBe(false)
			now += 0.05
			t.expect(intents:collect()).toBe(false)
			now += 0.05
			t.expect(intents:collect()).toBe(true)
			t.expect(intents:sell()).toBe(true)
			t.expect(intents:buyUpgrade("range")).toBe(true)
			t.expect(intents:unlockZone("zone_b")).toBe(true)
			t.expect(intents:buyUpgrade("" :: any)).toBe(false)
			t.expect(intents:unlockZone(42 :: any)).toBe(false)

			t.expect(fired).toEqual({
				{ "collect" },
				{ "collect" },
				{ "sell" },
				{ "buyUpgrade", "range" },
				{ "unlockZone", "zone_b" },
			})
			t.expect(type(Intents.fromRemotes)).toBe("function")
		end)

		t.it("104 round trip: server snapshot -> ClientState.apply -> get returns the same values", function()
			local snapshot = serverSnapshot()
			local state = ClientState.new()
			t.expect(state:apply(snapshot)).toBe(true)
			local received = state:get() :: any
			t.expect(received).toEqual(snapshot)
			t.expect(received ~= snapshot).toBe(true)
			t.expect(#received.items).toBe(8)
			t.expect(typeof(received.items[1].position)).toBe("Vector3")
			t.expect(received.items[1].position).toBe(snapshot.items[1].position)
		end)
	end)
end
