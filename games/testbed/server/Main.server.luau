--!strict
-- Server-Start des Testbeds: Welt aufbauen, dann die Engine mit der Testbed-Config starten.
-- DataStore ausschliesslich "testbed_profiles_v1".
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerRuntime = require(ServerScriptService:WaitForChild("FactoryCore").server.Engine.ServerRuntime)
local Testbed = require(ReplicatedStorage:WaitForChild("TestbedShared"):WaitForChild("Config"))
local World = require(script.Parent:WaitForChild("World"))

World.build(Testbed.config)
ServerRuntime.start(Testbed.config, {
	dataStoreName = "testbed_profiles_v1",
})
