--!strict
-- Selling 40-43: Inventar in Coins verwandeln.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local Economy = require(FactoryCore.server.Economy)
local Inventory = require(FactoryCore.server.Inventory)
local Modifiers = require(FactoryCore.server.Modifiers)
local Selling = require(FactoryCore.server.Selling)
local Upgrades = require(FactoryCore.server.Upgrades)

local CTX = { userId = 101 }
local PRICES = { item_a = 10, item_b = 25 }

type Env = {
	profile: { [string]: any },
	atSellPoint: boolean,
	economy: Economy.Economy,
	inventory: Inventory.Inventory,
	modifiers: Modifiers.Modifiers,
	selling: Selling.Selling,
	sales: { any },
}

local function newEnv(sellFactor: number?): Env
	local env = {} :: Env
	env.profile = {}
	env.atSellPoint = true
	env.sales = {}
	local function getProfile(ctx)
		return if ctx.userId == CTX.userId then env.profile else nil
	end
	env.economy = Economy.new({ getProfile = getProfile })
	env.inventory = Inventory.new({
		getProfile = getProfile,
		getCapacity = function()
			return 100
		end,
	})
	env.modifiers = Modifiers.new({ base = { sellFactor = sellFactor or 1 } })
	env.selling = Selling.new({
		inventory = env.inventory,
		economy = env.economy,
		modifiers = env.modifiers,
		prices = PRICES,
		canSell = function()
			return env.atSellPoint
		end,
		onSold = function(_ctx, sale)
			table.insert(env.sales, sale)
		end,
	})
	return env
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("selling", function()
		t.it("40 sale: earned = floor(sum * sellFactor), inventory empty, balance raised, onSold correct", function()
			local env = newEnv()
			env.inventory:add(CTX, "item_a", 3)
			env.inventory:add(CTX, "item_b", 1)

			local result = env.selling:sell(CTX)
			t.expect(result).toEqual({ earned = 55, sold = { item_a = 3, item_b = 1 } })
			t.expect(env.inventory:count(CTX)).toBe(0)
			t.expect(env.economy:balance(CTX)).toBe(55)
			t.expect(env.sales).toEqual({ { earned = 55, sold = { item_a = 3, item_b = 1 } } })

			-- Faktor 0: Inventar wird geleert, keine Gutschrift, kein Fehler.
			local zero = newEnv(0)
			zero.inventory:add(CTX, "item_a", 2)
			t.expect(zero.selling:sell(CTX)).toEqual({ earned = 0, sold = { item_a = 2 } })
			t.expect(zero.inventory:count(CTX)).toBe(0)
			t.expect(zero.economy:balance(CTX)).toBe(0)
		end)

		t.it("41 sellFactor via Modifiers (upgrade source mul 1.5) raises the earnings", function()
			local env = newEnv()
			local upgrades = Upgrades.new({
				getProfile = function()
					return env.profile
				end,
				economy = env.economy,
				dimensions = { sell_boost = { stat = "sellFactor", levels = { { cost = 10, mul = 1.5 } } } },
			})
			env.modifiers:registerSource("upgrades", upgrades:modifierSource())
			env.economy:credit(CTX, 10, "test_reward")
			t.expect(upgrades:purchase(CTX, "sell_boost")).toBe(true)
			env.inventory:add(CTX, "item_a", 3)
			env.inventory:add(CTX, "item_b", 1)

			local result = env.selling:sell(CTX)
			t.expect(result.earned).toBe(82) -- floor(55 * 1.5)
			t.expect(env.economy:balance(CTX)).toBe(82)
		end)

		t.it("42 NOT_AT_SELL_POINT, NOTHING_TO_SELL, UNKNOWN_ITEM: nothing cleared, no credit", function()
			local env = newEnv()
			t.expect(env.selling:sell(CTX)).toEqual({ earned = 0, sold = {}, err = "NOTHING_TO_SELL" })

			env.inventory:add(CTX, "item_a", 2)
			env.atSellPoint = false
			t.expect(env.selling:sell(CTX)).toEqual({ earned = 0, sold = {}, err = "NOT_AT_SELL_POINT" })
			t.expect(env.inventory:contents(CTX)).toEqual({ item_a = 2 })

			env.atSellPoint = true
			env.inventory:add(CTX, "item_unpriced", 1)
			t.expect(env.selling:sell(CTX)).toEqual({ earned = 0, sold = {}, err = "UNKNOWN_ITEM" })
			t.expect(env.inventory:contents(CTX)).toEqual({ item_a = 2, item_unpriced = 1 })
			t.expect(env.economy:balance(CTX)).toBe(0)
			t.expect(#env.sales).toBe(0)
			t.expect(env.selling:sell({ userId = 999 }).err).toBe("NOT_LOADED")
		end)

		t.it("43 corrupt balance: CORRUPT_VALUE, inventory kept", function()
			local env = newEnv()
			env.inventory:add(CTX, "item_a", 2)
			env.profile.coins = -5

			t.expect(env.selling:sell(CTX)).toEqual({ earned = 0, sold = {}, err = "CORRUPT_VALUE" })
			t.expect(env.inventory:contents(CTX)).toEqual({ item_a = 2 })
			t.expect(env.profile.coins).toBe(-5)
			t.expect(#env.sales).toBe(0)
		end)
	end)
end
