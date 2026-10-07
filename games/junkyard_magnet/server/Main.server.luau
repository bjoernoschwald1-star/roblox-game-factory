--!strict
-- Server-Start von Junkyard Magnet: Licht aus der Client-Config, Schrottplatz bauen, Engine starten, jedem Spieler
-- den Magneten als Werkzeug geben. DataStore "junkyard_profiles_v1"; im unveroeffentlichten Studio-Place
-- (PlaceId 0, DataStore nicht verfuegbar) laeuft das Spiel mit einem fluechtigen Speicher im Arbeitsspeicher -
-- Fortschritt verschwindet dann beim Beenden des Spieltests.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerRuntime = require(ServerScriptService:WaitForChild("FactoryCore").server.Engine.ServerRuntime)
local LightingProfile = require(ReplicatedStorage:WaitForChild("FactoryKit"):WaitForChild("LightingProfile"))
local ClientConfig = require(ReplicatedStorage:WaitForChild("JunkyardShared"):WaitForChild("ClientConfig"))
local ServerConfig = require(script.Parent:WaitForChild("ServerConfig"))
local World = require(script.Parent:WaitForChild("World"))
local PropShapes = require(script.Parent:WaitForChild("PropShapes"))

local _restore, lightingErrors = LightingProfile.apply(ClientConfig.lighting)
if #lightingErrors > 0 then
	warn("[Junkyard] lighting profile: " .. table.concat(lightingErrors, "; "))
end
World.build(ServerConfig)

-- Fluechtiger Speicher nur fuer den lokalen Studio-Place (Schnittstelle core/src/server/Storage/StorageAdapter).
local function memoryStorage(): any
	local data: { [string]: any } = {}
	return {
		read = function(_self, key: string)
			return true, data[key]
		end,
		update = function(_self, key: string, transform: (any) -> any)
			local ok, value = pcall(transform, data[key])
			if not ok then
				return false, value
			end
			if value ~= nil then
				data[key] = value
			end
			return true, data[key]
		end,
		remove = function(_self, key: string)
			local old = data[key]
			data[key] = nil
			return true, old
		end,
	}
end

ServerRuntime.start(ServerConfig, {
	dataStoreName = "junkyard_profiles_v1",
	storage = if game.PlaceId == 0 then memoryStorage() else nil,
})

-- Magnet-Werkzeug aus den Blender-Grundformen (tool_magnet), am Griff gehalten. Rein kosmetisch: Einsammeln laeuft
-- ueber die Absicht collect (der Client sendet sie beim Benutzen des Werkzeugs).
local MAGNET_SCALE = 2

local function magnetTool(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Magnet"
	tool.CanBeDropped = false
	tool.RequiresHandle = true
	-- Doppelt so gross wie das Art-Modell, damit der Magnet in der Hand gut zu sehen ist.
	local model = World.buildProp("tool_magnet", CFrame.new(), tool, false, MAGNET_SCALE)
	local size = (PropShapes :: any).tool_magnet.size
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 0.4, 0.4)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.Massless = true
	-- Griff oben am Bogen; Pole zeigen nach vorn-unten.
	handle.CFrame = CFrame.new(0, size[2] * MAGNET_SCALE - 0.4, 0)
	handle.Parent = tool
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") then
			child.Anchored = false
			child.CanCollide = false
			child.Massless = true
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = handle
			weld.Part1 = child
			weld.Parent = child
		end
	end
	tool.Grip = CFrame.Angles(math.rad(-70), 0, 0)
	return tool
end

local template = magnetTool()
local function equip(player: Player)
	player.CharacterAdded:Connect(function()
		local backpack = player:WaitForChild("Backpack")
		if backpack:FindFirstChild("Magnet") == nil then
			template:Clone().Parent = backpack
		end
	end)
	if player.Character ~= nil then
		template:Clone().Parent = player:WaitForChild("Backpack")
	end
end
Players.PlayerAdded:Connect(equip)
for _, player in Players:GetPlayers() do
	equip(player)
end
