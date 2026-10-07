--!strict
-- Absichtlich fehlschlagender Test fuer den Rot-Nachweis der Suite "red".
local Runner = require(game:GetService("ServerScriptService").FactoryCore.testing.Runner)

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("intentional", function()
		t.it("fails on purpose", function()
			t.expect(1 + 1).toBe(3)
		end)
	end)
end
