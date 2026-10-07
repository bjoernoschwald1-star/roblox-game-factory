--!strict
-- Tests 64-66: Config-Validator gegen die SampleConfig und gezielt kaputte Kopien.
local ServerScriptService = game:GetService("ServerScriptService")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local Validator = require(FactoryCore.server.Config.Validator)
local SampleConfig = require(ServerScriptService.FactoryCoreTests.fixtures.SampleConfig)

type Case = {
	code: string,
	path: string,
	breakIt: (config: any) -> (),
}

local function hasError(result: Validator.Result, code: string, path: string): boolean
	for _, err in result.errors do
		if err.code == code and err.path == path then
			return true
		end
	end
	return false
end

local CASES: { Case } = {
	{
		code = "MISSING_FIELD",
		path = "game.id",
		breakIt = function(config)
			config.game.id = nil
		end,
	},
	{
		code = "WRONG_TYPE",
		path = "items.item_small.price",
		breakIt = function(config)
			config.items.item_small.price = "2"
		end,
	},
	{
		code = "INVALID_ID",
		path = "items.Item-Big",
		breakIt = function(config)
			config.items["Item-Big"] = config.items.item_small
		end,
	},
	{
		code = "DUPLICATE_ID",
		-- Gemeldet wird die zweite Rolle in sortierter Reihenfolge (bundle_vip < coins_small).
		path = "products.coins_small.productId",
		breakIt = function(config)
			config.products.bundle_vip.productId = config.products.coins_small.productId
		end,
	},
	{
		code = "NOT_POSITIVE",
		path = "items.item_small.spawnWeight",
		breakIt = function(config)
			config.items.item_small.spawnWeight = 0
		end,
	},
	{
		code = "COSTS_NOT_INCREASING",
		path = "upgrades.capacity.levels[2].cost",
		breakIt = function(config)
			config.upgrades.capacity.levels[2].cost = 100
		end,
	},
	{
		code = "UNKNOWN_REFERENCE",
		path = "items.item_huge.zoneId",
		breakIt = function(config)
			config.items.item_huge.zoneId = "zone_x"
		end,
	},
	{
		code = "UNREACHABLE_ZONE",
		path = "zones.zone_c.condition.type",
		breakIt = function(config)
			config.zones.zone_c.condition = { type = "teleport" }
		end,
	},
	{
		code = "MISSING_ASSET",
		path = "items.item_small.asset",
		breakIt = function(config)
			config.items.item_small.asset = nil
		end,
	},
	{
		code = "EMPTY_REWARDS",
		path = "products.coins_small.rewards",
		breakIt = function(config)
			config.products.coins_small.rewards = {}
		end,
	},
	{
		code = "MISSING_TEXT",
		path = "zones.zone_b.nameKey",
		breakIt = function(config)
			config.texts.zone_b_name = nil
		end,
	},
	{
		code = "UNKNOWN_ENUM",
		path = "sell.trigger",
		breakIt = function(config)
			config.sell.trigger = "portal"
		end,
	},
	{
		code = "MISSING_REMOTE",
		path = "remotes.unlockZone",
		breakIt = function(config)
			config.remotes.unlockZone = nil
		end,
	},
}

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("config validator", function()
		t.it("64 SampleConfig is valid", function()
			local result = Validator.validate(SampleConfig())
			t.expect(Validator.format(result)).toBe("")
			t.expect(result.ok).toBe(true)
		end)

		t.it("65 every error class is reported with its path", function()
			for _, case in CASES do
				local config: any = SampleConfig()
				case.breakIt(config)
				local result = Validator.validate(config)
				t.expect({ case.code, result.ok }).toEqual({ case.code, false })
				t.expect({ case.code, case.path, hasError(result, case.code, case.path), Validator.format(result) })
					.toEqual({
						case.code,
						case.path,
						true,
						Validator.format(result),
					})
			end
			-- Der Original-Fixture bleibt unberuehrt.
			t.expect(Validator.validate(SampleConfig()).ok).toBe(true)
		end)

		t.it("66 several errors are all reported; validate never throws", function()
			local config: any = SampleConfig()
			config.game.id = nil
			config.upgrades.capacity.levels[2].cost = 100
			config.remotes.sell = nil
			local result = Validator.validate(config)
			t.expect(hasError(result, "MISSING_FIELD", "game.id")).toBe(true)
			t.expect(hasError(result, "COSTS_NOT_INCREASING", "upgrades.capacity.levels[2].cost")).toBe(true)
			t.expect(hasError(result, "MISSING_REMOTE", "remotes.sell")).toBe(true)
			t.expect(#result.errors).toBe(3)

			local nilCalled, nilResult = pcall(Validator.validate, nil)
			t.expect({ nilCalled, nilResult.ok }).toEqual({ true, false })
			t.expect(hasError(nilResult, "WRONG_TYPE", "")).toBe(true)
			for _, value in { 5, "config", true } do
				local called, invalid = pcall(Validator.validate, value)
				t.expect({ tostring(value), called, invalid.ok }).toEqual({ tostring(value), true, false })
				t.expect(hasError(invalid, "WRONG_TYPE", "")).toBe(true)
			end
			local called, empty = pcall(Validator.validate, {})
			t.expect(called).toBe(true)
			t.expect(hasError(empty, "MISSING_FIELD", "game")).toBe(true)
			t.expect(hasError(empty, "MISSING_REMOTE", "remotes.collect")).toBe(true)
			local weird: any = SampleConfig()
			weird.zones = { zone_a = 5 }
			weird.items = "none"
			t.expect((pcall(Validator.validate, weird))).toBe(true)
		end)
	end)
end
