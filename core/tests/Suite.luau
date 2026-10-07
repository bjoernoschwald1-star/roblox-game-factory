--!strict
-- Suite "core": alle Tests der Core Engine (ProfileStore/PlayerSession inkl. echtem DataStore,
-- Economy, Inventory, Collecting, Modifiers, Upgrades, Zones, Selling, der ganze Loop, Log, Monetization,
-- Analytics und RemoteGateway).
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
	require(script.Parent.LogSpec) :: Runner.Spec,
	require(script.Parent.MonetizationSpec) :: Runner.Spec,
	require(script.Parent.AnalyticsSpec) :: Runner.Spec,
	require(script.Parent.RemoteGatewaySpec) :: Runner.Spec,
	require(script.Parent.ConfigValidatorSpec) :: Runner.Spec,
	require(script.Parent.GameServerSpec) :: Runner.Spec,
	require(script.Parent.SimulatorSpec) :: Runner.Spec,
	require(script.Parent.EngineAdaptersSpec) :: Runner.Spec,
	require(script.Parent.ServerRuntimeSpec) :: Runner.Spec,
	require(script.Parent.StateSyncSpec) :: Runner.Spec,
	require(script.Parent.ClientSpec) :: Runner.Spec,
}

return Suite
