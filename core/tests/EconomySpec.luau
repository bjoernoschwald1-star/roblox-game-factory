--!strict
-- Economy 1-5: Kontostand mit reinem Fake-Profil.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local Economy = require(FactoryCore.server.Economy)

local CTX = { userId = 101 }

type Env = {
	profiles: { [number]: { [string]: any } },
	transactions: { { delta: number, balance: number, reason: string } },
	economy: Economy.Economy,
}

local function newEnv(options: { [string]: any }?): Env
	local env = {} :: Env
	env.profiles = { [CTX.userId] = {} }
	env.transactions = {}
	local config: { [string]: any } = {
		getProfile = function(ctx)
			return env.profiles[ctx.userId]
		end,
		onTransaction = function(_ctx, transaction)
			table.insert(env.transactions, transaction)
		end,
	}
	for name, value in options or {} do
		config[name] = value
	end
	env.economy = Economy.new(config :: any)
	return env
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("economy", function()
		t.it("01 credit raises, debit lowers, balance matches, onTransaction reports delta and reason", function()
			local env = newEnv()
			t.expect(env.economy:balance(CTX)).toBe(0)
			t.expect(env.profiles[CTX.userId].coins).toBe(0)

			t.expect(env.economy:credit(CTX, 50, "test_reward")).toBe(true)
			t.expect(env.economy:debit(CTX, 20, "test_purchase")).toBe(true)
			t.expect(env.economy:balance(CTX)).toBe(30)
			t.expect(env.profiles[CTX.userId].coins).toBe(30)
			t.expect(env.transactions).toEqual({
				{ delta = 50, balance = 50, reason = "test_reward" },
				{ delta = -20, balance = 30, reason = "test_purchase" },
			})
		end)

		t.it("02 debit above balance: INSUFFICIENT_FUNDS, balance unchanged, no onTransaction", function()
			local env = newEnv()
			env.economy:credit(CTX, 10, "test_reward")
			env.transactions = {}

			local ok, err = env.economy:debit(CTX, 11, "test_purchase")
			t.expect(ok).toBe(false)
			t.expect(err).toBe("INSUFFICIENT_FUNDS")
			t.expect(env.economy:balance(CTX)).toBe(10)
			t.expect(#env.transactions).toBe(0)
		end)

		t.it("03 invalid amounts and reasons: matching errors, no change", function()
			local env = newEnv()
			env.economy:credit(CTX, 7, "test_reward")
			env.transactions = {}

			for _, amount in { 0, -5, 1.5, 0 / 0, math.huge } do
				for _, operation in { "credit", "debit" } do
					local ok, err = (env.economy :: any)[operation](env.economy, CTX, amount, "test_reward")
					t.expect({ operation, tostring(amount), ok, err }).toEqual({
						operation,
						tostring(amount),
						false,
						"INVALID_AMOUNT",
					})
				end
			end
			for _, reason in { "", "Bad Reason", "1x" } do
				for _, operation in { "credit", "debit" } do
					local ok, err = (env.economy :: any)[operation](env.economy, CTX, 1, reason)
					t.expect({ operation, reason, ok, err }).toEqual({ operation, reason, false, "INVALID_REASON" })
				end
			end
			t.expect(env.economy:balance(CTX)).toBe(7)
			t.expect(#env.transactions).toBe(0)
		end)

		t.it("04 credit is capped at maxBalance and reports the actual delta", function()
			local env = newEnv({ maxBalance = 100 })
			env.economy:credit(CTX, 90, "test_reward")
			env.transactions = {}

			t.expect(env.economy:credit(CTX, 25, "test_reward")).toBe(true)
			t.expect(env.economy:balance(CTX)).toBe(100)
			t.expect(env.transactions).toEqual({ { delta = 10, balance = 100, reason = "test_reward" } })

			-- Bereits am Maximum: keine Aenderung, kein onTransaction.
			t.expect(env.economy:credit(CTX, 5, "test_reward")).toBe(true)
			t.expect(env.economy:balance(CTX)).toBe(100)
			t.expect(#env.transactions).toBe(1)
		end)

		t.it("05 without a loaded profile: NOT_LOADED, balance nil", function()
			local env = newEnv()
			local stranger = { userId = 999 }

			t.expect(env.economy:balance(stranger)).toBe(nil)
			local creditOk, creditErr = env.economy:credit(stranger, 5, "test_reward")
			t.expect({ creditOk, creditErr }).toEqual({ false, "NOT_LOADED" })
			local debitOk, debitErr = env.economy:debit(stranger, 5, "test_purchase")
			t.expect({ debitOk, debitErr }).toEqual({ false, "NOT_LOADED" })
			t.expect(#env.transactions).toBe(0)
		end)

		t.it("20 corrupt balance is never repaired: balance nil, CORRUPT_VALUE, profile unchanged", function()
			for _, corrupt in { "abc", -1, 1.5, 0 / 0, 101 } do
				local env = newEnv({ maxBalance = 100 })
				local profile = env.profiles[CTX.userId]
				profile.coins = corrupt
				local label = tostring(corrupt)

				t.expect({ label, env.economy:balance(CTX) }).toEqual({ label })
				local creditOk, creditErr = env.economy:credit(CTX, 5, "test_reward")
				t.expect({ label, creditOk, creditErr }).toEqual({ label, false, "CORRUPT_VALUE" })
				local debitOk, debitErr = env.economy:debit(CTX, 1, "test_purchase")
				t.expect({ label, debitOk, debitErr }).toEqual({ label, false, "CORRUPT_VALUE" })
				-- NaN ist sich selbst ungleich, daher Vergleich ueber tostring.
				t.expect({ label, tostring(profile.coins) }).toEqual({ label, label })
				t.expect({ label, #env.transactions }).toEqual({ label, 0 })
			end

			local env = newEnv()
			t.expect(env.economy:balance(CTX)).toBe(0)
			t.expect(env.profiles[CTX.userId].coins).toBe(0)
		end)
	end)
end
