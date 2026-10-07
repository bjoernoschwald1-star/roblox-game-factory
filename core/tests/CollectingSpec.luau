--!strict
-- Collecting 9-19: Spawner, gepruefte Aufnahme, Collect-Typ Radius und Zusammenspiel mit Inventory/Economy.
-- Fake-Profile, injizierte Uhr und Random.new(festerSeed); keine Instanzen im DataModel.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local Collecting = require(FactoryCore.server.Collecting)
local Radius = require(FactoryCore.server.CollectTypes.Radius)
local Inventory = require(FactoryCore.server.Inventory)
local Economy = require(FactoryCore.server.Economy)
local ProfileStore = require(FactoryCore.server.ProfileStore)
local PlayerSession = require(FactoryCore.server.PlayerSession)

local A = { userId = 101 }
local B = { userId = 202 }
local ORIGIN = Vector3.new(0, 0, 0)
local FAR = Vector3.new(1000, 0, 1000)

local ZONES = {
	zone_a = { density = 3, respawnSeconds = 10 },
	zone_b = { density = 2, respawnSeconds = 5 },
	zone_c = { density = 2, respawnSeconds = 5 },
}

local ITEMS = {
	item_a1 = { zoneId = "zone_a", spawnWeight = 3 },
	item_a2 = { zoneId = "zone_a", spawnWeight = 1 },
	item_b1 = { zoneId = "zone_b", spawnWeight = 1 },
	item_c1 = { zoneId = "zone_c", spawnWeight = 1 },
}

type Instance = Collecting.ItemInstance

type Env = {
	now: number,
	profiles: { [number]: { [string]: any } },
	capacity: number,
	range: number,
	unlocked: { [string]: boolean },
	positions: { [string]: { Vector3 } },
	collectedEvents: { { Instance } },
	inventory: Inventory.Inventory,
	collecting: Collecting.Collecting,
}

local function newEnv(overrides: { [string]: any }?): Env
	local env = {} :: Env
	env.now = 0
	env.profiles = { [A.userId] = {}, [B.userId] = {} }
	env.capacity = 50
	env.range = 10
	env.unlocked = { zone_a = true, zone_b = true, zone_c = false }
	env.positions = {}
	env.collectedEvents = {}
	env.inventory = Inventory.new({
		getProfile = function(ctx)
			return env.profiles[ctx.userId]
		end,
		getCapacity = function()
			return env.capacity
		end,
	})
	local options: { [string]: any } = {
		items = ITEMS,
		zones = ZONES,
		inventory = env.inventory,
		isZoneUnlocked = function(_ctx, zoneId: string): boolean
			return env.unlocked[zoneId] == true
		end,
		getRange = function(): number
			return env.range
		end,
		-- Feste Positionen aus env.positions (in Reihenfolge), sonst weit entfernt.
		spawnPosition = function(zoneId: string, rng: Random): Vector3
			local queue = env.positions[zoneId]
			if queue ~= nil and #queue > 0 then
				return table.remove(queue, 1) :: Vector3
			end
			return FAR + Vector3.new(rng:NextNumber(0, 10), 0, 0)
		end,
		collectType = Radius,
		collectParams = { radius = 100 },
		rangeTolerance = 2,
		rateLimit = { maxItems = 100, windowSeconds = 10 },
		clock = function(): number
			return env.now
		end,
		rng = Random.new(7),
		onCollected = function(_ctx, collected: { Instance })
			table.insert(env.collectedEvents, collected)
		end,
	}
	for name, value in overrides or {} do
		options[name] = value
	end
	env.collecting = Collecting.new(options :: any)
	return env
end

local function positionsOf(list: { Instance }): { Vector3 }
	local positions = {}
	for _, instance in list do
		table.insert(positions, instance.position)
	end
	return positions
end

local function countByZone(list: { Instance }): { [string]: number }
	local counts = {}
	for _, instance in list do
		counts[instance.zoneId] = (counts[instance.zoneId] or 0) + 1
	end
	return counts
end

local function allIdsUnique(list: { Instance }): boolean
	local seen = {}
	for _, instance in list do
		if seen[instance.instanceId] then
			return false
		end
		seen[instance.instanceId] = true
	end
	return true
end

local function instancesOf(env: Env, ctx: { userId: number }): { Instance }
	return env.collecting:instances(ctx) :: { Instance }
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("collecting", function()
		t.it("09 startPlayer fills only unlocked zones up to density with item types of that zone", function()
			local env = newEnv()
			t.expect(env.collecting:startPlayer(A)).toBe(true)
			local list = instancesOf(env, A)

			t.expect(countByZone(list)).toEqual({ zone_a = 3, zone_b = 2 })
			for _, instance in list do
				t.expect(ITEMS[instance.itemTypeId].zoneId).toBe(instance.zoneId)
			end
			t.expect(allIdsUnique(list)).toBe(true)
		end)

		t.it("10 collect takes only items within range including tolerance", function()
			local env = newEnv()
			env.positions.zone_a = { Vector3.new(5, 0, 0), Vector3.new(11.9, 0, 0), Vector3.new(12.1, 0, 0) }
			env.collecting:startPlayer(A)

			local result = env.collecting:collect(A, ORIGIN)
			t.expect(result.err).toBe(nil)
			t.expect(result.rejected).toBe(0)
			t.expect(positionsOf(result.collected)).toEqual({ Vector3.new(5, 0, 0), Vector3.new(11.9, 0, 0) })
			t.expect(env.inventory:count(A)).toBe(2)
			t.expect(countByZone(instancesOf(env, A))).toEqual({ zone_a = 1, zone_b = 2 })
			t.expect(#env.collectedEvents).toBe(1)
		end)

		t.it("11 item in a locked zone is not taken even within range", function()
			local env = newEnv()
			env.unlocked.zone_c = true
			env.positions.zone_c = { Vector3.new(1, 0, 0), Vector3.new(2, 0, 0) }
			env.collecting:startPlayer(A)
			env.unlocked.zone_c = false

			local result = env.collecting:collect(A, ORIGIN)
			t.expect(#result.collected).toBe(0)
			t.expect(result.rejected).toBe(0)
			t.expect(env.inventory:count(A)).toBe(0)
			t.expect(countByZone(instancesOf(env, A)).zone_c).toBe(2)
		end)

		t.it("12 nearly full inventory: only the nearest up to freeSpace, rest rejected, FULL", function()
			local env = newEnv()
			env.capacity = 2
			env.positions.zone_a = { Vector3.new(3, 0, 0), Vector3.new(1, 0, 0), Vector3.new(2, 0, 0) }
			env.collecting:startPlayer(A)

			local result = env.collecting:collect(A, ORIGIN)
			t.expect(result.err).toBe("FULL")
			t.expect(result.rejected).toBe(1)
			t.expect(positionsOf(result.collected)).toEqual({ Vector3.new(1, 0, 0), Vector3.new(2, 0, 0) })
			t.expect(env.inventory:count(A)).toBe(2)
			local remaining = instancesOf(env, A)
			t.expect(countByZone(remaining).zone_a).toBe(1)
			for _, instance in remaining do
				if instance.zoneId == "zone_a" then
					t.expect(instance.position).toBe(Vector3.new(3, 0, 0))
				end
			end
		end)

		t.it("13 malicious collect type: unknown, duplicate and out-of-range ids are rejected", function()
			local plan: { any } = {}
			local env = newEnv({
				collectType = {
					select = function()
						return plan
					end,
				},
			})
			env.positions.zone_a = { Vector3.new(1, 0, 0) }
			env.collecting:startPlayer(A)
			local near, far
			for _, instance in instancesOf(env, A) do
				if instance.position == Vector3.new(1, 0, 0) then
					near = instance.instanceId
				elseif instance.zoneId == "zone_b" then
					far = instance.instanceId
				end
			end
			for _, id in { "unknown_id", near, near, far, 42 } do
				table.insert(plan, id)
			end

			local result = env.collecting:collect(A, ORIGIN)
			t.expect(#result.collected).toBe(1)
			t.expect(result.collected[1].instanceId).toBe(near)
			t.expect(result.rejected).toBe(4)
			t.expect(env.inventory:count(A)).toBe(1)
			t.expect(#instancesOf(env, A)).toBe(4)
		end)

		t.it("14 collect type throws: COLLECT_TYPE_ERROR, nothing taken, inventory unchanged", function()
			local env = newEnv({
				collectType = {
					select = function(): { string }
						error("broken collect type")
					end,
				},
			})
			env.positions.zone_a = { Vector3.new(1, 0, 0) }
			env.collecting:startPlayer(A)

			local result = env.collecting:collect(A, ORIGIN)
			t.expect(result.err).toBe("COLLECT_TYPE_ERROR")
			t.expect(#result.collected).toBe(0)
			t.expect(env.inventory:count(A)).toBe(0)
			t.expect(#instancesOf(env, A)).toBe(5)
			t.expect(#env.collectedEvents).toBe(0)
		end)

		t.it("15 rate limit: pickups beyond maxItems per window are cut, allowed again after the window", function()
			local env = newEnv({
				zones = {
					zone_a = { density = 5, respawnSeconds = 100 },
					zone_b = { density = 0, respawnSeconds = 0 },
					zone_c = { density = 0, respawnSeconds = 0 },
				},
				rateLimit = { maxItems = 3, windowSeconds = 10 },
			})
			env.positions.zone_a = {}
			for i = 1, 5 do
				table.insert(env.positions.zone_a, Vector3.new(i, 0, 0))
			end
			env.collecting:startPlayer(A)

			local first = env.collecting:collect(A, ORIGIN)
			t.expect({ #first.collected, first.rejected, first.err }).toEqual({ 3, 2, "RATE_LIMITED" })

			env.now = 5
			local second = env.collecting:collect(A, ORIGIN)
			t.expect({ #second.collected, second.rejected, second.err }).toEqual({ 0, 2, "RATE_LIMITED" })

			env.now = 10
			local third = env.collecting:collect(A, ORIGIN)
			t.expect({ #third.collected, third.rejected, third.err }).toEqual({ 2, 0, nil })
			t.expect(env.inventory:count(A)).toBe(5)
		end)

		t.it(
			"16 respawn: a freed slot is not refilled before respawnSeconds, afterwards it is; ids stay unique",
			function()
				local env = newEnv({
					zones = {
						zone_a = { density = 1, respawnSeconds = 10 },
						zone_b = { density = 0, respawnSeconds = 0 },
						zone_c = { density = 0, respawnSeconds = 0 },
					},
				})
				env.positions.zone_a = { Vector3.new(1, 0, 0), Vector3.new(2, 0, 0) }
				env.collecting:startPlayer(A)
				local firstId = instancesOf(env, A)[1].instanceId

				t.expect(#env.collecting:collect(A, ORIGIN).collected).toBe(1)
				env.now = 9.9
				t.expect(env.collecting:refill(A)).toBe(true)
				t.expect(#instancesOf(env, A)).toBe(0)

				env.now = 10
				env.collecting:refill(A)
				local list = instancesOf(env, A)
				t.expect(#list).toBe(1)
				t.expect(list[1].instanceId ~= firstId).toBe(true)
				t.expect(list[1].position).toBe(Vector3.new(2, 0, 0))

				-- Bereits volle Zone wird nicht ueberfuellt.
				env.now = 100
				env.collecting:refill(A)
				t.expect(#instancesOf(env, A)).toBe(1)
			end
		)

		t.it("17 determinism: same seed yields the same item types and positions", function()
			local function spawnRun(seed: number): { any }
				local env = newEnv({
					rng = Random.new(seed),
					spawnPosition = function(_zoneId: string, rng: Random): Vector3
						return Vector3.new(rng:NextNumber(-50, 50), 0, rng:NextNumber(-50, 50))
					end,
				})
				env.collecting:startPlayer(A)
				local snapshot = {}
				for _, instance in instancesOf(env, A) do
					table.insert(snapshot, { instance.instanceId, instance.itemTypeId, instance.position })
				end
				return snapshot
			end

			local first = spawnRun(1234)
			t.expect(#first).toBe(5)
			t.expect(spawnRun(1234)).toEqual(first)
			-- Gegenprobe: ein anderer Seed fuehrt zu anderen Positionen.
			t.expect(spawnRun(4321)[1][3] ~= first[1][3]).toBe(true)
		end)

		t.it(
			"18 player isolation: A's items are neither visible nor collectable for B; stopPlayer(A) leaves B",
			function()
				local env = newEnv({
					spawnPosition = function(): Vector3
						return Vector3.new(1, 0, 0)
					end,
				})
				t.expect(env.collecting:collect(B, ORIGIN).err).toBe("NOT_STARTED")
				t.expect(env.collecting:instances(B)).toBe(nil)

				env.collecting:startPlayer(A)
				env.collecting:startPlayer(B)
				local beforeB = instancesOf(env, B)

				local resultA = env.collecting:collect(A, ORIGIN)
				t.expect(#resultA.collected).toBe(5)
				t.expect(instancesOf(env, B)).toEqual(beforeB)
				t.expect(env.inventory:count(B)).toBe(0)

				env.collecting:stopPlayer(A)
				t.expect(env.collecting:instances(A)).toBe(nil)
				t.expect(env.collecting:collect(A, ORIGIN).err).toBe("NOT_STARTED")
				t.expect(instancesOf(env, B)).toEqual(beforeB)

				local resultB = env.collecting:collect(B, ORIGIN)
				t.expect(#resultB.collected).toBe(5)
				t.expect(env.inventory:count(B)).toBe(5)
				t.expect(env.inventory:count(A)).toBe(5)
			end
		)

		t.it("19 collect -> inventory -> clear -> credit via economy (reason test_sell)", function()
			local memory = MemoryAdapter.new()
			local session = PlayerSession.new({
				store = ProfileStore.new({
					storage = memory,
					keyPrefix = "profile_",
					defaults = function()
						return { coins = 0, inventory = {} }
					end,
					schemaVersion = 1,
					serverId = "server-a",
					clock = function()
						return 1000
					end,
					sleep = function() end,
				}),
				onLoadFailed = function() end,
			})
			t.expect(session:join(A).state).toBe("NEW")
			local function getProfile(ctx)
				return session:get(ctx)
			end
			local economy = Economy.new({ getProfile = getProfile })
			local inventory = Inventory.new({
				getProfile = getProfile,
				getCapacity = function()
					return 10
				end,
			})
			local env = newEnv({
				inventory = inventory,
				spawnPosition = function(): Vector3
					return Vector3.new(1, 0, 0)
				end,
			})
			env.collecting:startPlayer(A)

			local result = env.collecting:collect(A, ORIGIN)
			t.expect(#result.collected).toBe(5)
			t.expect(inventory:count(A)).toBe(5)

			local prices = { item_a1 = 3, item_a2 = 5, item_b1 = 7 }
			local removed = inventory:clear(A) :: Inventory.Contents
			local total, items = 0, 0
			for itemTypeId, n in removed do
				total += prices[itemTypeId] * n
				items += n
			end
			t.expect(items).toBe(5)
			t.expect(economy:credit(A, total, "test_sell")).toBe(true)
			t.expect(economy:balance(A)).toBe(total)
			t.expect(inventory:count(A)).toBe(0)

			t.expect(session:autosaveAll()).toEqual({ saved = 1, failed = {} })
			local stored = memory:peek("profile_101")
			t.expect(stored.coins).toBe(total)
			t.expect(stored.inventory).toEqual({})
		end)

		t.it("22 throwing onTransaction and onCollected: booking and pickup still happen, results unchanged", function()
			local profiles = { [A.userId] = {} }
			local economy = Economy.new({
				getProfile = function(ctx)
					return profiles[ctx.userId]
				end,
				onTransaction = function()
					error("analytics down")
				end,
			})
			t.expect({ economy:credit(A, 40, "test_reward") }).toEqual({ true })
			t.expect({ economy:debit(A, 15, "test_purchase") }).toEqual({ true })
			t.expect(economy:balance(A)).toBe(25)

			local env = newEnv({
				onCollected = function()
					error("feedback down")
				end,
			})
			env.positions.zone_a = { Vector3.new(1, 0, 0) }
			env.collecting:startPlayer(A)
			local result = env.collecting:collect(A, ORIGIN)
			t.expect({ #result.collected, result.rejected, result.err }).toEqual({ 1, 0, nil })
			t.expect(env.inventory:count(A)).toBe(1)
			t.expect(#instancesOf(env, A)).toBe(4)
		end)

		t.it("23 Radius without params.radius follows getRange; a set params.radius stays an upper bound", function()
			local env = newEnv({ collectParams = {} })
			env.range = 5
			env.positions.zone_a = { Vector3.new(3, 0, 0), Vector3.new(10, 0, 0), Vector3.new(16, 0, 0) }
			env.collecting:startPlayer(A)

			local first = env.collecting:collect(A, ORIGIN)
			t.expect(positionsOf(first.collected)).toEqual({ Vector3.new(3, 0, 0) })
			-- Fake-Modifier: Reichweite steigt von 5 auf 15 (+ Toleranz 2 = 17).
			env.range = 15
			local second = env.collecting:collect(A, ORIGIN)
			t.expect(positionsOf(second.collected)).toEqual({ Vector3.new(10, 0, 0), Vector3.new(16, 0, 0) })

			local capped = newEnv({ collectParams = { radius = 6 } })
			capped.range = 15
			capped.positions.zone_a = { Vector3.new(3, 0, 0), Vector3.new(10, 0, 0), Vector3.new(16, 0, 0) }
			capped.collecting:startPlayer(A)
			local limited = capped.collecting:collect(A, ORIGIN)
			t.expect(positionsOf(limited.collected)).toEqual({ Vector3.new(3, 0, 0) })
			t.expect(countByZone(instancesOf(capped, A)).zone_a).toBe(2)
		end)

		t.it("24 constructor: zone with density > 0 and no items fails, density 0 without items is allowed", function()
			local function zonesWith(extra: { density: number, respawnSeconds: number }): { [string]: any }
				local zones: { [string]: any } = table.clone(ZONES)
				zones.zone_empty = extra
				return zones
			end
			local failedOk, failedErr = pcall(newEnv, { zones = zonesWith({ density = 2, respawnSeconds = 1 }) })
			t.expect(failedOk).toBe(false)
			t.expect(string.find(tostring(failedErr), "zone_empty", 1, true) ~= nil).toBe(true)
			local allowedOk = pcall(newEnv, { zones = zonesWith({ density = 0, respawnSeconds = 1 }) })
			t.expect(allowedOk).toBe(true)
		end)
	end)
end
