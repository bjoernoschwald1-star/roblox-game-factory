--!strict
-- Bindet die festen Remotes an Server-Handler. Die echte Implementierung legt in ReplicatedStorage einen Ordner
-- "FactoryRemotes" mit je einem RemoteEvent pro Name an; vorhandene gleichnamige Instanzen werden
-- wiederverwendet, nicht dupliziert. Antworten an den Client gibt es nie (nur RemoteEvent, keine RemoteFunction).
-- fireClient(name, player, payload) sendet Server -> Client ueber ein RemoteEvent im selben Ordner (z. B.
-- "stateUpdate"); fuer diese Remotes gibt es keinen OnServerEvent-Handler, Client-Aufrufe darauf verpuffen.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/RemoteEvent#OnServerEvent
--       https://create.roblox.com/docs/reference/engine/classes/RemoteEvent#FireClient
local PlayersAdapter = require(script.Parent.PlayersAdapter)

export type RemoteBinder = {
	bind: (self: RemoteBinder, name: string, handler: (player: any, ...any) -> ()) -> PlayersAdapter.Connection,
	fireClient: (self: RemoteBinder, name: string, player: any, payload: any) -> (),
}

local FOLDER_NAME = "FactoryRemotes"
local STATE_REMOTE = "stateUpdate"

local RemoteBinder = {}

RemoteBinder.FOLDER_NAME = FOLDER_NAME
RemoteBinder.STATE_REMOTE = STATE_REMOTE

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

	-- Liefert das RemoteEvent mit diesem Namen und legt es nur an, wenn es fehlt.
	local function remoteEvent(name: string): RemoteEvent
		local container = folder()
		local remote = container:FindFirstChild(name)
		if remote == nil then
			local created = Instance.new("RemoteEvent")
			created.Name = name
			created.Parent = container
			remote = created
		end
		assert(remote:IsA("RemoteEvent"), "RemoteBinder: " .. name .. " exists but is not a RemoteEvent")
		return remote :: RemoteEvent
	end

	local binder: RemoteBinder = {
		bind = function(_self, name: string, handler: (player: any, ...any) -> ()): PlayersAdapter.Connection
			return remoteEvent(name).OnServerEvent:Connect(handler)
		end,

		fireClient = function(_self, name: string, player: any, payload: any)
			remoteEvent(name):FireClient(player, payload)
		end,
	}
	return binder
end

return RemoteBinder
