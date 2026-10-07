--!strict
-- Suite "core": alle Tests der Core Engine (ProfileStore/PlayerSession inkl. echtem DataStore,
-- Economy, Inventory, Collecting).
local Runner = require(game:GetService("ServerScriptService").FactoryCore.testing.Runner)

local Suite: { Runner.Spec } = {
	require(script.Parent.ProfileStoreSpec) :: Runner.Spec,
	require(script.Parent.DataStoreIntegrationSpec) :: Runner.Spec,
	require(script.Parent.EconomySpec) :: Runner.Spec,
	require(script.Parent.InventorySpec) :: Runner.Spec,
	require(script.Parent.CollectingSpec) :: Runner.Spec,
}

return Suite
