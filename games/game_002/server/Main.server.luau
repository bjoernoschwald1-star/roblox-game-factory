--!strict
-- Server-Start des Probe-Raums von Game #002 (Forschungsstation): Licht ueber das Kit-Profil, Module laden, Raum
-- bauen. Reine Optik-Probe ohne Engine-Spielregeln, ohne DataStore und ohne Remotes; Lichttechnik
-- (LightingStyle, PrioritizeLightingQuality, Technology) setzt game002-probe.project.json.
-- Offene Punkte: fuer ein echtes Spiel fehlen Config, GameServer und Spielablauf (siehe Bericht zur Look-Probe).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local LightingProfile = require(ReplicatedStorage:WaitForChild("FactoryKit"):WaitForChild("LightingProfile"))
local ProbeConfig = require(ReplicatedStorage:WaitForChild("Game002Shared"):WaitForChild("ProbeConfig"))
local ModelAssets = require(script.Parent:WaitForChild("ModelAssets"))
local Room = require(script.Parent:WaitForChild("Room"))

local _restore, lightingErrors = LightingProfile.apply(ProbeConfig.lighting)
if #lightingErrors > 0 then
	warn("[Game002] lighting profile: " .. table.concat(lightingErrors, "; "))
end

local templates, failed = Room.loadModules(ModelAssets, ServerStorage:WaitForChild("Game002Surfaces"))
if #failed > 0 then
	warn("[Game002] Module nicht geladen: " .. table.concat(failed, "; "))
end
Room.build(templates, ProbeConfig, workspace)
