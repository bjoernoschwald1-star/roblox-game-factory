--!strict
local Runner = require(game:GetService("ServerScriptService").FactoryCore.testing.Runner)

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("trivial", function()
		t.it("adds numbers", function()
			t.expect(1 + 1).toBe(2)
			t.expect({ a = 1, b = { 2, 3 } }).toEqual({ a = 1, b = { 2, 3 } })
		end)
	end)
end
