--!strict
-- Inventory 6-8: Kapazitaet und Inhalt mit reinem Fake-Profil.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local Inventory = require(FactoryCore.server.Inventory)
local Collecting = require(FactoryCore.server.Collecting)
local Radius = require(FactoryCore.server.CollectTypes.Radius)
local TableCopy = require(FactoryCore.shared.TableCopy)

local CTX = { userId = 101 }

type Env = {
	profiles: { [number]: { [string]: any } },
	capacity: number,
	inventory: Inventory.Inventory,
}

local function newEnv(capacity: number): Env
	local env = {} :: Env
	env.profiles = { [CTX.userId] = {} }
	env.capacity = capacity
	env.inventory = Inventory.new({
		getProfile = function(ctx)
			return env.profiles[ctx.userId]
		end,
		getCapacity = function()
			return env.capacity
		end,
	})
	return env
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("inventory", function()
		t.it("06 add up to capacity, then FULL without partial change; count and freeSpace match", function()
			local env = newEnv(5)
			t.expect(env.inventory:freeSpace(CTX)).toBe(5)
			t.expect(env.inventory:add(CTX, "item_a", 3)).toBe(true)
			t.expect(env.inventory:add(CTX, "item_b", 1)).toBe(true)
			t.expect(env.inventory:count(CTX)).toBe(4)
			t.expect(env.inventory:freeSpace(CTX)).toBe(1)

			local ok, err = env.inventory:add(CTX, "item_b", 2)
			t.expect({ ok, err }).toEqual({ false, "FULL" })
			t.expect(env.inventory:contents(CTX)).toEqual({ item_a = 3, item_b = 1 })

			t.expect(env.inventory:add(CTX, "item_b", 1)).toBe(true)
			t.expect(env.inventory:count(CTX)).toBe(5)
			t.expect(env.inventory:freeSpace(CTX)).toBe(0)
		end)

		t.it("07 lowered capacity: freeSpace 0 instead of negative, add returns FULL", function()
			local env = newEnv(4)
			env.inventory:add(CTX, "item_a", 4)
			env.capacity = 2

			t.expect(env.inventory:freeSpace(CTX)).toBe(0)
			t.expect(env.inventory:count(CTX)).toBe(4)
			local ok, err = env.inventory:add(CTX, "item_a", 1)
			t.expect({ ok, err }).toEqual({ false, "FULL" })
			t.expect(env.inventory:contents(CTX)).toEqual({ item_a = 4 })
		end)

		t.it("08 clear returns removed contents and empties; invalid item or amount are rejected", function()
			local env = newEnv(10)
			env.inventory:add(CTX, "item_a", 2)
			env.inventory:add(CTX, "item_b", 3)

			t.expect(env.inventory:clear(CTX)).toEqual({ item_a = 2, item_b = 3 })
			t.expect(env.inventory:count(CTX)).toBe(0)
			t.expect(env.inventory:contents(CTX)).toEqual({})
			t.expect(env.inventory:clear(CTX)).toEqual({})

			for _, itemTypeId in { "", 42, false } do
				local ok, err = env.inventory:add(CTX, itemTypeId :: any, 1)
				t.expect({ ok, err }).toEqual({ false, "INVALID_ITEM" })
			end
			for _, n in { 0, -1, 1.5, 0 / 0, math.huge } do
				local ok, err = env.inventory:add(CTX, "item_a", n)
				t.expect({ tostring(n), ok, err }).toEqual({ tostring(n), false, "INVALID_AMOUNT" })
			end
			t.expect(env.inventory:count(CTX)).toBe(0)
			t.expect(env.inventory:count({ userId = 999 })).toBe(nil)
			t.expect(env.inventory:clear({ userId = 999 })).toBe(nil)
		end)

		t.it("21 corrupt inventory is never repaired: reads nil, add CORRUPT_VALUE, collect CORRUPT_VALUE", function()
			local cases: { { label: string, value: any } } = {
				{ label = "number", value = 5 },
				{ label = "zero count", value = { item_a = 0 } },
				{ label = "fractional count", value = { item_a = 1.5 } },
				{ label = "empty key", value = { [""] = 1 } },
			}
			for _, case in cases do
				local env = newEnv(10)
				local profile = env.profiles[CTX.userId]
				profile.inventory = case.value
				local snapshot = TableCopy.copy(case.value)
				local collecting = Collecting.new({
					items = { item_a = { zoneId = "zone_a", spawnWeight = 1 } },
					zones = { zone_a = { density = 1, respawnSeconds = 0 } },
					inventory = env.inventory,
					isZoneUnlocked = function()
						return true
					end,
					getRange = function()
						return 10
					end,
					spawnPosition = function()
						return Vector3.new(1, 0, 0)
					end,
					collectType = Radius,
					collectParams = {},
					rateLimit = { maxItems = 10, windowSeconds = 10 },
					clock = function()
						return 0
					end,
					rng = Random.new(1),
				})
				collecting:startPlayer(CTX)

				local label = case.label
				t.expect({ label, env.inventory:count(CTX) }).toEqual({ label })
				t.expect({ label, env.inventory:freeSpace(CTX) }).toEqual({ label })
				t.expect({ label, env.inventory:contents(CTX) }).toEqual({ label })
				local ok, err = env.inventory:add(CTX, "item_a", 1)
				t.expect({ label, ok, err }).toEqual({ label, false, "CORRUPT_VALUE" })
				t.expect({ label, env.inventory:clear(CTX) }).toEqual({ label })
				local result = collecting:collect(CTX, Vector3.new(0, 0, 0))
				t.expect({ label, result.err, #result.collected }).toEqual({ label, "CORRUPT_VALUE", 0 })
				t.expect({ label, profile.inventory }).toEqual({ label, snapshot })
			end
		end)
	end)
end
