--!strict
-- Suite-Definitionen: "red" = "green" + ein absichtlich fehlschlagender Test; "core" = Tests der Core Engine.
-- Jede Suite ist eine Funktion, die ihre Specs erst beim Aufruf per require laedt. So reisst ein Fehler
-- in FactoryCoreTests oder den Core-Modulen die Suiten "green" und "red" nicht mit.
local ServerScriptService = game:GetService("ServerScriptService")
local Runner = require(ServerScriptService.FactoryCore.testing.Runner)
local specs = script.Parent.specs

local function spikeSpecs(withFailing: boolean): { Runner.Spec }
	local list: { Runner.Spec } = {
		require(specs.Trivial) :: Runner.Spec,
		require(specs.DataStore) :: Runner.Spec,
	}
	if withFailing then
		table.insert(list, require(specs.Failing) :: Runner.Spec)
	end
	return list
end

local Suites: { [string]: () -> { Runner.Spec } } = {
	green = function()
		return spikeSpecs(false)
	end,
	red = function()
		return spikeSpecs(true)
	end,
	core = function()
		return require(ServerScriptService.FactoryCoreTests.Suite) :: { Runner.Spec }
	end,
}

return Suites
