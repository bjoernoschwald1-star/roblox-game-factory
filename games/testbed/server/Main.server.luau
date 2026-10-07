--!strict
-- Server-Start des Testbeds: Licht aus der Client-Config anwenden (Lighting repliziert zu den Clients), Welt
-- aufbauen, dann die Engine mit der Server-Config starten. DataStore ausschliesslich "testbed_profiles_v1".
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerRuntime = require(ServerScriptService:WaitForChild("FactoryCore").server.Engine.ServerRuntime)
local LightingProfile = require(ReplicatedStorage:WaitForChild("FactoryKit"):WaitForChild("LightingProfile"))
local ClientConfig = require(ReplicatedStorage:WaitForChild("TestbedShared"):WaitForChild("ClientConfig"))
local ServerConfig = require(script.Parent:WaitForChild("ServerConfig"))
local World = require(script.Parent:WaitForChild("World"))

local _restore, lightingErrors = LightingProfile.apply(ClientConfig.lighting)
if #lightingErrors > 0 then
	-- Einmalig beim Start, kein Takt: ungueltige Werte im Licht-Profil sichtbar machen.
	warn("[Testbed] lighting profile: " .. table.concat(lightingErrors, "; "))
end
World.build(ServerConfig)
ServerRuntime.start(ServerConfig, {
	dataStoreName = "testbed_profiles_v1",
})
