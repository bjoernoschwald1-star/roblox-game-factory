--!strict
-- Zones 33-39: Freischaltungen mit registrierbaren Bedingungen.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local Economy = require(FactoryCore.server.Economy)
local TableCopy = require(FactoryCore.shared.TableCopy)
local Upgrades = require(FactoryCore.server.Upgrades)
local Zones = require(FactoryCore.server.Zones)

local CTX = { userId = 101 }

local ZONES = {
	start = { order = 1, condition = { type = "always" } },
	coins_zone = { order = 2, condition = { type = "coinsAtLeast", amount = 50 } },
	buy_zone = { order = 3, condition = { type = "purchase", cost = 30 } },
	level_zone = { order = 4, condition = { type = "upgradeLevel", dimension = "range_boost", level = 2 } },
}

type Env = {
	profile: { [string]: any },
	economy: Economy.Economy,
	upgrades: Upgrades.Upgrades,
	zones: Zones.Zones,
	unlocked: { string },
}

local function newEnv(overrides: { [string]: any }?): Env
	local env = {} :: Env
	env.profile = {}
	env.unlocked = {}
	local function getProfile(ctx)
		return if ctx.userId == CTX.userId then env.profile else nil
	end
	env.economy = Economy.new({ getProfile = getProfile })
	env.upgrades = Upgrades.new({
		getProfile = getProfile,
		economy = env.economy,
		dimensions = {
			range_boost = { stat = "range", levels = { { cost = 10, add = 5 }, { cost = 20, add = 10 } } },
		},
	})
	local options: { [string]: any } = {
		getProfile = getProfile,
		zones = ZONES,
		economy = env.economy,
		upgrades = env.upgrades,
		onUnlocked = function(_ctx, event)
			table.insert(env.unlocked, event.zoneId)
		end,
	}
	-- false in overrides entfernt eine Option (z. B. economy = false fuer "Abhaengigkeit fehlt").
	for name, value in overrides or {} do
		options[name] = if value == false then nil else value
	end
	env.zones = Zones.new(options :: any)
	return env
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("zones", function()
		t.it("33 start zone (always) is free without profile entry; tryUnlock gives ALREADY_UNLOCKED", function()
			local env = newEnv()
			t.expect(env.zones:validate()).toBe(true)
			t.expect(env.zones:isUnlocked(CTX, "start")).toBe(true)
			t.expect(env.zones:isUnlocked(CTX, "coins_zone")).toBe(false)
			local ok, err = env.zones:tryUnlock(CTX, "start")
			t.expect({ ok, err }).toEqual({ false, "ALREADY_UNLOCKED" })
			t.expect(env.zones:unlockedZones(CTX)).toEqual({ "start" })
			t.expect(env.zones:isUnlocked({ userId = 999 }, "start")).toBe(false)
			t.expect(env.zones:isUnlocked(CTX, "unknown")).toBe(false)
			local unknownOk, unknownErr = env.zones:tryUnlock(CTX, "unknown")
			t.expect({ unknownOk, unknownErr }).toEqual({ false, "UNKNOWN_ZONE" })
		end)

		t.it("34 coinsAtLeast: below threshold CONDITION_NOT_MET, at threshold unlocked, balance unchanged", function()
			local env = newEnv()
			env.economy:credit(CTX, 49, "test_reward")
			local ok, err, reason = env.zones:tryUnlock(CTX, "coins_zone")
			t.expect({ ok, err, reason }).toEqual({ false, "CONDITION_NOT_MET", "INSUFFICIENT_FUNDS" })
			t.expect(env.zones:isUnlocked(CTX, "coins_zone")).toBe(false)

			env.economy:credit(CTX, 1, "test_reward")
			t.expect(env.zones:tryUnlock(CTX, "coins_zone")).toBe(true)
			t.expect(env.zones:isUnlocked(CTX, "coins_zone")).toBe(true)
			t.expect(env.economy:balance(CTX)).toBe(50)
			t.expect(env.unlocked).toEqual({ "coins_zone" })
			t.expect(env.profile.zones).toEqual({ coins_zone = true })
		end)

		t.it("35 purchase: debits and unlocks; with too few coins nothing is debited and it stays locked", function()
			local env = newEnv()
			env.profile.zones = { coins_zone = true }
			env.economy:credit(CTX, 29, "test_reward")
			local ok, err = env.zones:tryUnlock(CTX, "buy_zone")
			t.expect({ ok, err }).toEqual({ false, "CONDITION_NOT_MET" })
			t.expect(env.economy:balance(CTX)).toBe(29)
			t.expect(env.zones:isUnlocked(CTX, "buy_zone")).toBe(false)

			env.economy:credit(CTX, 11, "test_reward")
			t.expect(env.zones:tryUnlock(CTX, "buy_zone")).toBe(true)
			t.expect(env.economy:balance(CTX)).toBe(10)
			t.expect(env.zones:isUnlocked(CTX, "buy_zone")).toBe(true)
		end)

		t.it("36 upgradeLevel: unlocked only from the required level on", function()
			local env = newEnv()
			env.profile.zones = { coins_zone = true, buy_zone = true }
			env.economy:credit(CTX, 1000, "test_reward")

			local ok, err, reason = env.zones:tryUnlock(CTX, "level_zone")
			t.expect({ ok, err, reason }).toEqual({ false, "CONDITION_NOT_MET", "LEVEL_TOO_LOW" })
			env.upgrades:purchase(CTX, "range_boost")
			t.expect((env.zones:tryUnlock(CTX, "level_zone"))).toBe(false)
			env.upgrades:purchase(CTX, "range_boost")
			t.expect(env.zones:tryUnlock(CTX, "level_zone")).toBe(true)
			t.expect(env.zones:unlockedZones(CTX)).toEqual({ "start", "coins_zone", "buy_zone", "level_zone" })
		end)

		t.it("37 PREVIOUS_LOCKED: zone 3 cannot be unlocked before zone 2", function()
			local env = newEnv()
			env.economy:credit(CTX, 1000, "test_reward")
			local ok, err = env.zones:tryUnlock(CTX, "buy_zone")
			t.expect({ ok, err }).toEqual({ false, "PREVIOUS_LOCKED" })
			t.expect(env.economy:balance(CTX)).toBe(1000)
			t.expect(env.zones:isUnlocked(CTX, "buy_zone")).toBe(false)
		end)

		t.it("38 custom condition is used; missing dependency and unknown condition type are detected", function()
			local flags: { [string]: boolean } = {}
			local env = newEnv({
				zones = {
					start = { order = 1, condition = { type = "always" } },
					task_zone = { order = 2, condition = { type = "testFlag", flag = "done" } },
				},
			})
			local valid, problem = env.zones:validate()
			t.expect(valid).toBe(false)
			t.expect(string.find(tostring(problem), "testFlag", 1, true) ~= nil).toBe(true)
			local unknownOk, unknownErr = env.zones:tryUnlock(CTX, "task_zone")
			t.expect({ unknownOk, unknownErr }).toEqual({ false, "UNKNOWN_CONDITION" })

			env.zones:registerCondition("testFlag", function(_ctx, params): (boolean, string?)
				return flags[params.flag] == true, if flags[params.flag] then nil else "FLAG_MISSING"
			end)
			t.expect(env.zones:validate()).toBe(true)
			local ok, err, reason = env.zones:tryUnlock(CTX, "task_zone")
			t.expect({ ok, err, reason }).toEqual({ false, "CONDITION_NOT_MET", "FLAG_MISSING" })
			flags.done = true
			t.expect(env.zones:tryUnlock(CTX, "task_zone")).toBe(true)

			local noEconomy = newEnv({ economy = false })
			local depOk, depErr = noEconomy.zones:tryUnlock(CTX, "coins_zone")
			t.expect({ depOk, depErr }).toEqual({ false, "MISSING_DEPENDENCY" })
		end)

		t.it("39 corrupt zones field: CORRUPT_VALUE, only the start zone counts as unlocked", function()
			for _, corrupt in { "bad", { coins_zone = 1 }, { [""] = true } } do
				local env = newEnv()
				env.economy:credit(CTX, 1000, "test_reward")
				env.profile.zones = corrupt
				local snapshot = TableCopy.copy(corrupt)
				local label = type(corrupt) == "table" and "table" or tostring(corrupt)

				t.expect({ label, env.zones:isUnlocked(CTX, "start") }).toEqual({ label, true })
				t.expect({ label, env.zones:isUnlocked(CTX, "coins_zone") }).toEqual({ label, false })
				local ok, err = env.zones:tryUnlock(CTX, "coins_zone")
				t.expect({ label, ok, err }).toEqual({ label, false, "CORRUPT_VALUE" })
				t.expect({ label, env.zones:unlockedZones(CTX) }).toEqual({ label })
				t.expect({ label, env.profile.zones }).toEqual({ label, snapshot })
				t.expect({ label, env.economy:balance(CTX) }).toEqual({ label, 1000 })
			end
		end)
	end)
end
