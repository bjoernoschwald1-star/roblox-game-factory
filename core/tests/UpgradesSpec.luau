--!strict
-- Upgrades 28-32: Stufen kaufen, Wirkung ueber Modifiers, beschaedigte Stufen.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local Economy = require(FactoryCore.server.Economy)
local Modifiers = require(FactoryCore.server.Modifiers)
local TableCopy = require(FactoryCore.shared.TableCopy)
local Upgrades = require(FactoryCore.server.Upgrades)

local CTX = { userId = 101 }

local DIMENSIONS = {
	range_boost = {
		stat = "range",
		levels = { { cost = 10, add = 5 }, { cost = 25, add = 12 }, { cost = 60, add = 20 } },
	},
	capacity_boost = {
		stat = "capacity",
		levels = { { cost = 15, mul = 2 } },
	},
}

type Env = {
	profile: { [string]: any },
	economy: Economy.Economy,
	upgrades: Upgrades.Upgrades,
	events: { Upgrades.Purchase },
}

local function newEnv(): Env
	local env = {} :: Env
	env.profile = {}
	env.events = {}
	local function getProfile(ctx)
		return if ctx.userId == CTX.userId then env.profile else nil
	end
	env.economy = Economy.new({ getProfile = getProfile })
	env.upgrades = Upgrades.new({
		getProfile = getProfile,
		economy = env.economy,
		dimensions = DIMENSIONS,
		onUpgraded = function(_ctx, purchase)
			table.insert(env.events, purchase)
		end,
	})
	return env
end

local function dimensionsWith(levels: { any }, dimension: string?): { [string]: any }
	return { [dimension or "dim"] = { stat = "range", levels = levels } }
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("upgrades", function()
		t.it("28 purchase debits cost and raises the level; nextCost rises; MAX_LEVEL without debit", function()
			local env = newEnv()
			env.economy:credit(CTX, 100, "test_reward")
			t.expect(env.upgrades:level(CTX, "range_boost")).toBe(0)
			t.expect(env.upgrades:nextCost(CTX, "range_boost")).toBe(10)

			t.expect(env.upgrades:purchase(CTX, "range_boost")).toBe(true)
			t.expect(env.upgrades:level(CTX, "range_boost")).toBe(1)
			t.expect(env.economy:balance(CTX)).toBe(90)
			t.expect(env.upgrades:nextCost(CTX, "range_boost")).toBe(25)

			t.expect(env.upgrades:purchase(CTX, "range_boost")).toBe(true)
			t.expect(env.upgrades:purchase(CTX, "range_boost")).toBe(true)
			t.expect(env.upgrades:level(CTX, "range_boost")).toBe(3)
			t.expect(env.economy:balance(CTX)).toBe(5)
			t.expect(env.upgrades:nextCost(CTX, "range_boost")).toBe(nil)

			local ok, err = env.upgrades:purchase(CTX, "range_boost")
			t.expect({ ok, err }).toEqual({ false, "MAX_LEVEL" })
			t.expect(env.economy:balance(CTX)).toBe(5)
			t.expect(env.events).toEqual({
				{ dimension = "range_boost", level = 1, cost = 10 },
				{ dimension = "range_boost", level = 2, cost = 25 },
				{ dimension = "range_boost", level = 3, cost = 60 },
			})
			local unknownOk, unknownErr = env.upgrades:purchase(CTX, "nope")
			t.expect({ unknownOk, unknownErr }).toEqual({ false, "UNKNOWN_DIMENSION" })
		end)

		t.it("29 not enough coins: INSUFFICIENT_FUNDS, level and balance unchanged", function()
			local env = newEnv()
			env.economy:credit(CTX, 9, "test_reward")
			local ok, err = env.upgrades:purchase(CTX, "range_boost")
			t.expect({ ok, err }).toEqual({ false, "INSUFFICIENT_FUNDS" })
			t.expect(env.upgrades:level(CTX, "range_boost")).toBe(0)
			t.expect(env.economy:balance(CTX)).toBe(9)
			t.expect(#env.events).toBe(0)
		end)

		t.it("30 modifierSource: range rises with the level, using the entry of the current level", function()
			local env = newEnv()
			local modifiers = Modifiers.new({ base = { range = 10, capacity = 20 } })
			modifiers:registerSource("upgrades", env.upgrades:modifierSource())
			env.economy:credit(CTX, 1000, "test_reward")

			t.expect(modifiers:value(CTX, "range")).toBe(10)
			env.upgrades:purchase(CTX, "range_boost")
			t.expect(modifiers:value(CTX, "range")).toBe(15)
			env.upgrades:purchase(CTX, "range_boost")
			-- Stufe 2 nutzt nur ihren eigenen Eintrag (+12), nicht +5 und +12.
			t.expect(modifiers:value(CTX, "range")).toBe(22)
			env.upgrades:purchase(CTX, "capacity_boost")
			t.expect(modifiers:value(CTX, "capacity")).toBe(40)
			t.expect(modifiers:value({ userId = 999 }, "range")).toBe(10)
		end)

		t.it("31 constructor rejects non-rising or non-positive costs and invalid dimension ids", function()
			local env = newEnv()
			local function build(dimensions: { [string]: any }): boolean
				return (
					pcall(Upgrades.new, {
						getProfile = function()
							return {}
						end,
						economy = env.economy,
						dimensions = dimensions,
					})
				)
			end
			t.expect(build(dimensionsWith({ { cost = 10, add = 1 }, { cost = 10, add = 2 } }))).toBe(false)
			t.expect(build(dimensionsWith({ { cost = 10, add = 1 }, { cost = 5, add = 2 } }))).toBe(false)
			t.expect(build(dimensionsWith({ { cost = 0, add = 1 } }))).toBe(false)
			t.expect(build(dimensionsWith({ { cost = 1.5, add = 1 } }))).toBe(false)
			t.expect(build(dimensionsWith({ { cost = 10 } }))).toBe(false)
			t.expect(build(dimensionsWith({}))).toBe(false)
			t.expect(build(dimensionsWith({ { cost = 10, add = 1 } }, "Bad-Dim"))).toBe(false)
			t.expect(build(dimensionsWith({ { cost = 10, add = 1 }, { cost = 20, mul = 1.5 } }))).toBe(true)
		end)

		t.it("32 corrupt level: CORRUPT_VALUE, nothing changed, source has no effect", function()
			for _, corrupt in { -1, 1.5, 4, "x" } do
				local env = newEnv()
				local modifiers = Modifiers.new({ base = { range = 10, capacity = 20 } })
				modifiers:registerSource("upgrades", env.upgrades:modifierSource())
				env.economy:credit(CTX, 100, "test_reward")
				env.profile.upgrades = { range_boost = corrupt }
				local snapshot = TableCopy.copy(env.profile.upgrades)
				local label = tostring(corrupt)

				t.expect({ label, env.upgrades:level(CTX, "range_boost") }).toEqual({ label })
				t.expect({ label, env.upgrades:nextCost(CTX, "range_boost") }).toEqual({ label })
				local ok, err = env.upgrades:purchase(CTX, "capacity_boost")
				t.expect({ label, ok, err }).toEqual({ label, false, "CORRUPT_VALUE" })
				t.expect({ label, env.economy:balance(CTX) }).toEqual({ label, 100 })
				t.expect({ label, env.profile.upgrades }).toEqual({ label, snapshot })
				t.expect({ label, modifiers:value(CTX, "range") }).toEqual({ label, 10 })
			end

			local env = newEnv()
			env.profile.upgrades = "not a table"
			t.expect(env.upgrades:level(CTX, "range_boost")).toBe(nil)
			t.expect(env.profile.upgrades).toBe("not a table")
		end)
	end)
end
