--!strict
-- Modifiers 25-27: Verrechnung von Bonusquellen.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local Modifiers = require(FactoryCore.server.Modifiers)

local CTX = { userId = 101 }

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("modifiers", function()
		t.it("25 base value without sources; add and mul from two sources: (base + adds) * muls", function()
			local modifiers = Modifiers.new({ base = { range = 10, capacity = 5 } })
			t.expect(modifiers:value(CTX, "range")).toBe(10)

			modifiers:registerSource("b_source", function()
				return { range = { add = 5, mul = 2 } }
			end)
			modifiers:registerSource("a_source", function()
				return { range = { add = 3 }, capacity = { mul = 1.5 } }
			end)
			t.expect(modifiers:value(CTX, "range")).toBe((10 + 5 + 3) * 2)
			t.expect(modifiers:value(CTX, "capacity")).toBe(7.5)
		end)

		t.it("26 throwing source and invalid effects are ignored; result never negative", function()
			local modifiers = Modifiers.new({ base = { range = 10 } })
			modifiers:registerSource("good", function()
				return { range = { add = 2 } }
			end)
			modifiers:registerSource("throws", function(): { [string]: any }
				error("source down")
			end)
			modifiers:registerSource("nan_mul", function()
				return { range = { mul = 0 / 0 } }
			end)
			modifiers:registerSource("negative_mul", function()
				return { range = { mul = -1 } }
			end)
			modifiers:registerSource("no_table", function(): any
				return 5
			end)
			t.expect(modifiers:value(CTX, "range")).toBe(12)

			local floor = Modifiers.new({ base = { range = 0 } })
			floor:registerSource("minus", function()
				return { range = { add = -5 } }
			end)
			t.expect(floor:value(CTX, "range")).toBe(0)
		end)

		t.it("27 duplicate source name, unknown stat and invalid base abort via assert", function()
			local modifiers = Modifiers.new({ base = { range = 10 } })
			local function source()
				return {}
			end
			modifiers:registerSource("once", source)
			t.expect((pcall(modifiers.registerSource, modifiers, "once", source))).toBe(false)
			t.expect((pcall(modifiers.value, modifiers, CTX, "unknown_stat"))).toBe(false)
			t.expect((pcall(Modifiers.new, { base = { range = -1 } }))).toBe(false)
			t.expect((pcall(Modifiers.new, { base = { range = 0 / 0 } }))).toBe(false)
		end)
	end)
end
