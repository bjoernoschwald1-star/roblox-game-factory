--!strict
-- Suite "core": alle Tests der Core Engine (ProfileStore/PlayerSession inkl. echtem DataStore,
-- Economy, Inventory, Collecting, Modifiers, Upgrades, Zones, Selling und der ganze Loop).
local Runner = require(game:GetService("ServerScriptService").FactoryCore.testing.Runner)

local Suite: { Runner.Spec } = {
	require(script.Parent.ProfileStoreSpec) :: Runner.Spec,
	require(script.Parent.DataStoreIntegrationSpec) :: Runner.Spec,
	require(script.Parent.EconomySpec) :: Runner.Spec,
	require(script.Parent.InventorySpec) :: Runner.Spec,
	require(script.Parent.CollectingSpec) :: Runner.Spec,
	require(script.Parent.ModifiersSpec) :: Runner.Spec,
	require(script.Parent.UpgradesSpec) :: Runner.Spec,
	require(script.Parent.ZonesSpec) :: Runner.Spec,
	require(script.Parent.SellingSpec) :: Runner.Spec,
	require(script.Parent.LoopSpec) :: Runner.Spec,
}

return Suite
