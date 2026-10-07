--!strict
-- Tests 74-76: Economy-Simulator mit der SampleConfig.
local ServerScriptService = game:GetService("ServerScriptService")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local Simulator = require(FactoryCore.server.Config.Simulator)
local SampleConfig = require(ServerScriptService.FactoryCoreTests.fixtures.SampleConfig)

local OPTIONS: Simulator.Options = { maxMinutes = 120, buyPolicy = "cheapest_first" }

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("simulator", function()
		t.it("74 SampleConfig: deterministic, all zones reached, milestones in order", function()
			local report = Simulator.run(SampleConfig(), OPTIONS)
			t.expect(Simulator.run(SampleConfig(), OPTIONS)).toEqual(report)
			t.expect(report.reachedAllZones).toBe(true)

			local firstSell = report.minutesToFirstSell :: number
			local firstUpgrade = report.minutesToFirstUpgrade :: number
			local zone2 = report.minutesToZone[2] :: number
			local zone3 = report.minutesToZone[3] :: number
			t.expect(firstSell <= firstUpgrade).toBe(true)
			t.expect(zone2 <= zone3).toBe(true)
			t.expect(report.minutesToZone[1]).toBe(0)
			print(
				string.format(
					"[spike] SIM sample firstSell=%s firstUpgrade=%s zone2=%s zone3=%s coinsAtEnd=%d levels=range:%d,capacity:%d,sell_bonus:%d",
					tostring(firstSell),
					tostring(firstUpgrade),
					tostring(zone2),
					tostring(zone3),
					report.coinsAtEnd,
					report.upgradeLevels.range,
					report.upgradeLevels.capacity,
					report.upgradeLevels.sell_bonus
				)
			)
		end)

		t.it("75 zone 3 too expensive: not all zones reached, zone 3 nil, check reports a violation", function()
			local config: any = SampleConfig()
			config.zones.zone_c.condition = { type = "purchase", cost = 1000000000 }
			local report = Simulator.run(config, { maxMinutes = 60, buyPolicy = "cheapest_first" })
			t.expect(report.reachedAllZones).toBe(false)
			t.expect(report.minutesToZone[3]).toBe(nil)
			t.expect(report.minutesToZone[2] ~= nil).toBe(true)

			local result = Simulator.check(report, { zone3MaxMinutes = 60 })
			t.expect(result.ok).toBe(false)
			t.expect(result.violations).toEqual({ { name = "zone3MaxMinutes", limit = 60 } })
		end)

		t.it("76 check: limits just met pass, just missed give a violation naming the limit", function()
			local report = Simulator.run(SampleConfig(), OPTIONS)
			local firstUpgrade = report.minutesToFirstUpgrade :: number
			local zone2 = report.minutesToZone[2] :: number
			local zone3 = report.minutesToZone[3] :: number

			local met = Simulator.check(report, {
				firstUpgradeMaxMinutes = firstUpgrade,
				zone2MaxMinutes = zone2,
				zone3MaxMinutes = zone3,
			})
			t.expect(met).toEqual({ ok = true, violations = {} })

			local missed = Simulator.check(report, {
				firstUpgradeMaxMinutes = firstUpgrade,
				zone2MaxMinutes = zone2,
				zone3MaxMinutes = zone3 - 0.01,
			})
			t.expect(missed.ok).toBe(false)
			t.expect(missed.violations).toEqual({ { name = "zone3MaxMinutes", limit = zone3 - 0.01, actual = zone3 } })
		end)
	end)
end
