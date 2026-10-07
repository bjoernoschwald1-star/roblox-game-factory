--!strict
-- Tests 49-55 und 63: Developer Products (idempotent, Rueckbau bei Speicherfehlern) und Game Passes.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local TableCopy = require(FactoryCore.shared.TableCopy)
local ProfileStore = require(FactoryCore.server.ProfileStore)
local PlayerSession = require(FactoryCore.server.PlayerSession)
local Economy = require(FactoryCore.server.Economy)
local Inventory = require(FactoryCore.server.Inventory)
local Modifiers = require(FactoryCore.server.Modifiers)
local Upgrades = require(FactoryCore.server.Upgrades)
local Collecting = require(FactoryCore.server.Collecting)
local Radius = require(FactoryCore.server.CollectTypes.Radius)
local Monetization = require(FactoryCore.server.Monetization)

local CTX = { userId = 101 }
local KEY = "profile_101"
local COIN_PACK = 1001
local BUNDLE = 1002

local PRODUCTS = {
	[COIN_PACK] = { role = "coins_small", rewards = { { type = "coins", amount = 100 } } },
	[BUNDLE] = { role = "bundle_vip", rewards = { { type = "coins", amount = 50 }, { type = "perk", perkId = "vip" } } },
}
local PASSES = {
	double_range = { passId = 2001, effects = { range = { mul = 2 } } },
}

type Server = {
	session: PlayerSession.PlayerSession,
	economy: Economy.Economy,
	monetization: Monetization.Monetization,
	owned: { [number]: any },
	events: { { role: string, purchaseId: string } },
	getProfile: (ctx: { userId: number }) -> { [string]: any }?,
}

local function newStore(memory: MemoryAdapter.MemoryAdapter, serverId: string): ProfileStore.ProfileStore
	return ProfileStore.new({
		storage = memory,
		keyPrefix = "profile_",
		defaults = function()
			return { coins = 0 }
		end,
		schemaVersion = 1,
		serverId = serverId,
		clock = function()
			return 1000
		end,
		sleep = function() end,
	})
end

local function newServer(memory: MemoryAdapter.MemoryAdapter, serverId: string): Server
	local server = {} :: Server
	server.owned = {}
	server.events = {}
	server.session = PlayerSession.new({ store = newStore(memory, serverId), onLoadFailed = function() end })
	server.getProfile = function(ctx)
		return server.session:get(ctx)
	end
	server.economy = Economy.new({ getProfile = server.getProfile })
	server.monetization = Monetization.new({
		getProfile = server.getProfile,
		session = server.session,
		economy = server.economy,
		products = PRODUCTS,
		passes = PASSES,
		ownsPass = function(_userId: number, passId: number): boolean
			local owned = server.owned[passId]
			if owned == "throw" then
				error("pass service down")
			end
			return owned == true
		end,
		maxRemembered = 3,
		onPurchase = function(_ctx, purchase)
			table.insert(server.events, purchase)
		end,
	})
	return server
end

local function receipt(purchaseId: string, productId: number?, playerId: number?): Monetization.Receipt
	return { PurchaseId = purchaseId, PlayerId = playerId or CTX.userId, ProductId = productId or COIN_PACK }
end

local function joined(memory: MemoryAdapter.MemoryAdapter, serverId: string): Server
	local server = newServer(memory, serverId)
	server.session:join(CTX)
	return server
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("monetization", function()
		t.it("49 coin purchase: granted, balance raised, PurchaseId stored, onPurchase called", function()
			local memory = MemoryAdapter.new()
			local server = joined(memory, "server-a")

			t.expect(server.monetization:processReceipt(receipt("p1"))).toBe("PurchaseGranted")
			t.expect(server.economy:balance(CTX)).toBe(100)
			t.expect(memory:peek(KEY).coins).toBe(100)
			t.expect(memory:peek(KEY).purchases).toEqual({ "p1" })
			t.expect(server.events).toEqual({ { role = "coins_small", purchaseId = "p1" } })
		end)

		t.it("50 same receipt twice: second time granted without another credit", function()
			local memory = MemoryAdapter.new()
			local server = joined(memory, "server-a")

			t.expect(server.monetization:processReceipt(receipt("p1"))).toBe("PurchaseGranted")
			t.expect(server.monetization:processReceipt(receipt("p1"))).toBe("PurchaseGranted")
			t.expect(server.economy:balance(CTX)).toBe(100)
			t.expect(memory:peek(KEY).coins).toBe(100)
			t.expect(#server.events).toBe(1)
		end)

		t.it("51 save fails: NotProcessedYet, balance and purchases as before; retry grants exactly once", function()
			local memory = MemoryAdapter.new()
			local server = joined(memory, "server-a")
			local profile = server.getProfile(CTX) :: { [string]: any }

			memory:failUpdates(3)
			t.expect(server.monetization:processReceipt(receipt("p1"))).toBe("NotProcessedYet")
			t.expect(server.economy:balance(CTX)).toBe(0)
			t.expect(profile.purchases).toEqual({})
			t.expect(memory:peek(KEY).coins).toBe(0)
			t.expect(#server.events).toBe(0)

			t.expect(server.monetization:processReceipt(receipt("p1"))).toBe("PurchaseGranted")
			t.expect(server.economy:balance(CTX)).toBe(100)
			t.expect(memory:peek(KEY).coins).toBe(100)
			t.expect(memory:peek(KEY).purchases).toEqual({ "p1" })
			t.expect(#server.events).toBe(1)
		end)

		t.it("52 written but reported as failed: NotProcessedYet with rollback; next attempt credits once", function()
			local memory = MemoryAdapter.new()
			local server = joined(memory, "server-a")
			local profile = server.getProfile(CTX) :: { [string]: any }

			memory:failUpdatesAfterWrite(3)
			t.expect(server.monetization:processReceipt(receipt("p1"))).toBe("NotProcessedYet")
			t.expect(server.economy:balance(CTX)).toBe(0)
			t.expect(profile.purchases).toEqual({})
			-- Der Speicher hat den Kauf trotz Fehlermeldung bereits.
			t.expect(memory:peek(KEY).coins).toBe(100)

			t.expect(server.monetization:processReceipt(receipt("p1"))).toBe("PurchaseGranted")
			t.expect(server.economy:balance(CTX)).toBe(100)
			t.expect(memory:peek(KEY).coins).toBe(100)
			t.expect(memory:peek(KEY).purchases).toEqual({ "p1" })
			t.expect(#server.events).toBe(1)
		end)

		t.it("53 server switch: receipt on server B grants without double credit; LOCK_LOST rolls back", function()
			local memory = MemoryAdapter.new()
			local serverA = joined(memory, "server-a")
			t.expect(serverA.monetization:processReceipt(receipt("p1"))).toBe("PurchaseGranted")
			t.expect(serverA.session:leave(CTX)).toBe(true)

			local serverB = newServer(memory, "server-b")
			t.expect(serverB.session:join(CTX).state).toBe("LOADED")
			t.expect(serverB.monetization:processReceipt(receipt("p1"))).toBe("PurchaseGranted")
			t.expect(serverB.economy:balance(CTX)).toBe(100)
			t.expect(#serverB.events).toBe(0)

			local taken = memory:peek(KEY)
			taken.session = { serverId = "server-c", timestamp = 1000 }
			memory:seed(KEY, taken)
			t.expect(serverB.monetization:processReceipt(receipt("p2", BUNDLE))).toBe("NotProcessedYet")
			t.expect(serverB.economy:balance(CTX)).toBe(100)
			t.expect(serverB.monetization:hasPerk(CTX, "vip")).toBe(false)
			local profile = serverB.getProfile(CTX) :: { [string]: any }
			t.expect(profile.purchases).toEqual({ "p1" })
			t.expect(memory:peek(KEY)).toEqual(taken)
		end)

		t.it("54 bundle grants coins and perk; unknown product and unloaded player change nothing", function()
			local memory = MemoryAdapter.new()
			local server = joined(memory, "server-a")

			t.expect(server.monetization:processReceipt(receipt("p1", BUNDLE))).toBe("PurchaseGranted")
			t.expect(server.economy:balance(CTX)).toBe(50)
			t.expect(server.monetization:hasPerk(CTX, "vip")).toBe(true)
			t.expect(server.monetization:hasPerk(CTX, "other")).toBe(false)
			t.expect(memory:peek(KEY).perks).toEqual({ vip = true })

			t.expect(server.monetization:processReceipt(receipt("p9", 9999))).toBe("NotProcessedYet")
			t.expect(server.monetization:processReceipt(receipt("p9", COIN_PACK, 999))).toBe("NotProcessedYet")
			t.expect(server.monetization:processReceipt(receipt(""))).toBe("NotProcessedYet")
			t.expect(server.economy:balance(CTX)).toBe(50)

			for _, purchaseId in { "p2", "p3", "p4" } do
				t.expect(server.monetization:processReceipt(receipt(purchaseId))).toBe("PurchaseGranted")
			end
			t.expect(server.economy:balance(CTX)).toBe(350)
			t.expect(memory:peek(KEY).purchases).toEqual({ "p4", "p3", "p2" })
		end)

		t.it(
			"55 game pass: refreshPasses feeds Modifiers; throwing ownsPass means not owned; profile unchanged",
			function()
				local memory = MemoryAdapter.new()
				local server = joined(memory, "server-a")
				local profile = server.getProfile(CTX) :: { [string]: any }
				local snapshot = TableCopy.copy(profile)
				local modifiers = Modifiers.new({ base = { range = 10 } })
				modifiers:registerSource("passes", server.monetization:modifierSource())

				t.expect(modifiers:value(CTX, "range")).toBe(10)
				server.owned[2001] = true
				server.monetization:refreshPasses(CTX)
				t.expect(modifiers:value(CTX, "range")).toBe(20)

				server.owned[2001] = "throw"
				server.monetization:refreshPasses(CTX)
				t.expect(modifiers:value(CTX, "range")).toBe(10)

				t.expect(server.monetization:setPassOwned(CTX, "double_range", true)).toBe(true)
				t.expect(modifiers:value(CTX, "range")).toBe(20)
				local unknownOk, unknownErr = server.monetization:setPassOwned(CTX, "nope", true)
				t.expect({ unknownOk, unknownErr }).toEqual({ false, "UNKNOWN_PASS" })
				server.monetization:clearPlayer(CTX)
				t.expect(modifiers:value(CTX, "range")).toBe(10)
				t.expect(profile).toEqual(snapshot)
			end
		)

		t.it("63 pass doubles getRange in Collecting; coin pack funds an upgrade; consistent after reload", function()
			local memory = MemoryAdapter.new()
			local server = joined(memory, "server-a")
			local modifiers = Modifiers.new({ base = { range = 5, capacity = 10 } })
			local upgrades = Upgrades.new({
				getProfile = server.getProfile,
				economy = server.economy,
				dimensions = { range_boost = { stat = "range", levels = { { cost = 100, add = 5 } } } },
			})
			modifiers:registerSource("passes", server.monetization:modifierSource())
			modifiers:registerSource("upgrades", upgrades:modifierSource())
			local inventory = Inventory.new({
				getProfile = server.getProfile,
				getCapacity = function(ctx)
					return math.floor(modifiers:value(ctx, "capacity"))
				end,
			})
			local positions = { Vector3.new(3, 0, 0), Vector3.new(10, 0, 0) }
			local collecting = Collecting.new({
				items = { item_a = { zoneId = "zone_a", spawnWeight = 1 } },
				zones = { zone_a = { density = 2, respawnSeconds = 0 } },
				inventory = inventory,
				isZoneUnlocked = function()
					return true
				end,
				getRange = function(ctx)
					return modifiers:value(ctx, "range")
				end,
				spawnPosition = function(): Vector3
					return table.remove(positions, 1) :: Vector3
				end,
				collectType = Radius,
				collectParams = {},
				rangeTolerance = 2,
				rateLimit = { maxItems = 100, windowSeconds = 10 },
				clock = function()
					return 0
				end,
				rng = Random.new(5),
			})
			collecting:startPlayer(CTX)

			-- Pass verdoppelt die Reichweite: 5 -> 10 (+ Toleranz 2), das Item bei 10 Studs wird erreichbar.
			t.expect(modifiers:value(CTX, "range")).toBe(5)
			server.owned[2001] = true
			server.monetization:refreshPasses(CTX)
			t.expect(modifiers:value(CTX, "range")).toBe(10)
			t.expect(#collecting:collect(CTX, Vector3.new(0, 0, 0)).collected).toBe(2)

			-- Coin-Pack finanziert das Upgrade: (5 + 5) * 2 = 20.
			t.expect(upgrades:purchase(CTX, "range_boost")).toBe(false)
			t.expect(server.monetization:processReceipt(receipt("p1"))).toBe("PurchaseGranted")
			t.expect(upgrades:purchase(CTX, "range_boost")).toBe(true)
			t.expect(modifiers:value(CTX, "range")).toBe(20)

			t.expect(server.session:autosaveAll()).toEqual({ saved = 1, failed = {} })
			t.expect(server.session:leave(CTX)).toBe(true)
			local reloaded = newStore(memory, "server-b"):load(CTX)
			t.expect(reloaded.state).toBe("LOADED")
			local profile = reloaded.profile :: ProfileStore.Profile
			t.expect(profile.coins).toBe(0)
			t.expect(profile.upgrades).toEqual({ range_boost = 1 })
			t.expect(profile.purchases).toEqual({ "p1" })
			t.expect(profile.inventory).toEqual({ item_a = 2 })
			-- Der Pass-Effekt ist nirgends im Profil gespeichert.
			local keys = {}
			for key in profile do
				table.insert(keys, key)
			end
			table.sort(keys)
			t.expect(keys).toEqual({
				"coins",
				"firstSeen",
				"inventory",
				"lastSeen",
				"perks",
				"purchases",
				"schemaVersion",
				"session",
				"upgrades",
			})
		end)
	end)
end
