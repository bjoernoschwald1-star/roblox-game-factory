--!strict
-- Duenner Adapter um den Players-Dienst. Spieler-Objekte sind fuer den Rest der Runtime undurchsichtig (any),
-- damit Tests Fake-Spieler ({ UserId, GetJoinData, Kick, Character }) verwenden koennen.
--
-- joinSource liest Player:GetJoinData().LaunchData (Text oder JSON, gesetzt ueber Share-Links bzw.
-- ExperienceInviteOptions.LaunchData): "paid" oder "organic" als reiner Text oder als JSON-Feld source;
-- alles andere sowie Fehler beim Lesen ergeben "unknown".
-- Doku: https://create.roblox.com/docs/reference/engine/classes/Players
--       https://create.roblox.com/docs/reference/engine/classes/Player#GetJoinData
local HttpService = game:GetService("HttpService")

export type Connection = {
	Disconnect: (self: any) -> (),
}

export type PlayersAdapter = {
	onAdded: (self: PlayersAdapter, callback: (player: any) -> ()) -> Connection,
	onRemoving: (self: PlayersAdapter, callback: (player: any) -> ()) -> Connection,
	getPlayers: (self: PlayersAdapter) -> { any },
	kick: (self: PlayersAdapter, player: any, message: string) -> (),
	joinSource: (self: PlayersAdapter, player: any) -> string,
}

local SOURCES = { paid = true, organic = true }

local PlayersAdapter = {}

-- Leitet die Herkunft aus LaunchData ab; wirft nie.
function PlayersAdapter.joinSourceOf(player: any): string
	local ok, data = pcall(function()
		return player:GetJoinData()
	end)
	if not ok or type(data) ~= "table" or type(data.LaunchData) ~= "string" then
		return "unknown"
	end
	local launchData = data.LaunchData
	if SOURCES[launchData] then
		return launchData
	end
	local decoded, parsed = pcall(function()
		return HttpService:JSONDecode(launchData)
	end)
	if decoded and type(parsed) == "table" and type(parsed.source) == "string" and SOURCES[parsed.source] then
		return parsed.source
	end
	return "unknown"
end

function PlayersAdapter.new(playersService: Players?): PlayersAdapter
	local players: Players = playersService or game:GetService("Players")
	local adapter: PlayersAdapter = {
		onAdded = function(_self, callback: (player: any) -> ()): Connection
			return players.PlayerAdded:Connect(callback)
		end,
		onRemoving = function(_self, callback: (player: any) -> ()): Connection
			return players.PlayerRemoving:Connect(function(player: Player)
				callback(player)
			end)
		end,
		getPlayers = function(_self): { any }
			return players:GetPlayers()
		end,
		kick = function(_self, player: any, message: string)
			pcall(function()
				player:Kick(message)
			end)
		end,
		joinSource = function(_self, player: any): string
			return PlayersAdapter.joinSourceOf(player)
		end,
	}
	return adapter
end

return PlayersAdapter
