--!strict
-- Bindet die festen Remotes an Server-Handler. Die echte Implementierung legt in ReplicatedStorage einen Ordner
-- "FactoryRemotes" mit je einem RemoteEvent pro Name an; vorhandene gleichnamige Instanzen werden
-- wiederverwendet, nicht dupliziert. Antworten an den Client gibt es nie (nur RemoteEvent, keine RemoteFunction).
-- Doku: https://create.roblox.com/docs/reference/engine/classes/RemoteEvent#OnServerEvent
local PlayersAdapter = require(script.Parent.PlayersAdapter)

export type RemoteBinder = {
	bind: (self: RemoteBinder, name: string, handler: (player: any, ...any) -> ()) -> PlayersAdapter.Connection,
}

local FOLDER_NAME = "FactoryRemotes"

local RemoteBinder = {}

RemoteBinder.FOLDER_NAME = FOLDER_NAME

function RemoteBinder.new(parent: Instance?): RemoteBinder
	local root: Instance = parent or game:GetService("ReplicatedStorage")

	local function folder(): Instance
		local existing = root:FindFirstChild(FOLDER_NAME)
		if existing ~= nil then
			return existing
		end
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		created.Parent = root
		return created
	end

	local binder: RemoteBinder = {
		bind = function(_self, name: string, handler: (player: any, ...any) -> ()): PlayersAdapter.Connection
			local container = folder()
			local remote = container:FindFirstChild(name)
			if remote == nil then
				local created = Instance.new("RemoteEvent")
				created.Name = name
				created.Parent = container
				remote = created
			end
			assert(remote:IsA("RemoteEvent"), "RemoteBinder: " .. name .. " exists but is not a RemoteEvent")
			return (remote :: RemoteEvent).OnServerEvent:Connect(handler)
		end,
	}
	return binder
end

return RemoteBinder
