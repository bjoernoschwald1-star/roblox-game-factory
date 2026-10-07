--!strict
-- Suite "core": alle Tests der Core Engine (12 mit MemoryAdapter, 1 gegen den echten DataStore).
local Runner = require(game:GetService("ServerScriptService").FactoryCore.testing.Runner)

local Suite: { Runner.Spec } = {
	require(script.Parent.ProfileStoreSpec) :: Runner.Spec,
	require(script.Parent.DataStoreIntegrationSpec) :: Runner.Spec,
}

return Suite
