--!strict
-- Verwaltet die geladenen Profile pro userId auf Basis eines ProfileStore.
-- Keine Anbindung an Players/PlayerAdded/BindToClose: Die Spiel-Anbindung ruft join/leave/autosaveAll/shutdown.
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)
local ProfileStore = require(script.Parent.ProfileStore)

type PlayerContext = PlayerContext.PlayerContext
type Profile = ProfileStore.Profile
type LoadState = ProfileStore.LoadState
type LoadResult = ProfileStore.LoadResult

export type Options = {
	store: ProfileStore.ProfileStore,
	-- Wird bei LOCKED, FAILED und FUTURE_VERSION aufgerufen (im Spiel: Hinweis anzeigen, Spieler entfernen).
	onLoadFailed: (ctx: PlayerContext, state: LoadState, err: string?) -> (),
}

export type SaveReport = {
	saved: number,
	failed: { { userId: number, error: string } },
}

export type PlayerSession = {
	join: (self: PlayerSession, ctx: PlayerContext) -> LoadResult,
	get: (self: PlayerSession, ctx: PlayerContext) -> Profile?,
	autosaveAll: (self: PlayerSession) -> SaveReport,
	leave: (self: PlayerSession, ctx: PlayerContext) -> (boolean, string?),
	shutdown: (self: PlayerSession) -> SaveReport,
}

type Entry = {
	ctx: PlayerContext,
	profile: Profile,
}

local PlayerSession = {}

function PlayerSession.new(options: Options): PlayerSession
	local store = options.store
	local entries: { [number]: Entry } = {}
	-- true waehrend des Ladens; false, wenn der Spieler waehrenddessen gegangen ist.
	local loading: { [number]: boolean } = {}

	local function snapshot(): { Entry }
		local list = {}
		for _, entry in entries do
			table.insert(list, entry)
		end
		return list
	end

	local function report(): SaveReport
		return { saved = 0, failed = {} }
	end

	local session: PlayerSession

	session = {
		join = function(_self, ctx: PlayerContext): LoadResult
			local userId = ctx.userId
			local existing = entries[userId]
			if existing ~= nil then
				return { state = ProfileStore.State.LOADED, profile = existing.profile }
			end
			if loading[userId] ~= nil then
				return { state = ProfileStore.State.FAILED, error = "JOIN_IN_PROGRESS" }
			end

			loading[userId] = true
			local result = store:load(ctx)
			local stillPresent = loading[userId]
			loading[userId] = nil

			local profile = result.profile
			if profile ~= nil then
				if stillPresent then
					entries[userId] = { ctx = ctx, profile = profile }
				else
					-- Spieler ist waehrend des Ladens gegangen: Lock sofort wieder freigeben.
					store:release(ctx, profile)
				end
			elseif stillPresent then
				options.onLoadFailed(ctx, result.state, result.error)
			end
			return result
		end,

		get = function(_self, ctx: PlayerContext): Profile?
			local entry = entries[ctx.userId]
			return if entry ~= nil then entry.profile else nil
		end,

		autosaveAll = function(_self): SaveReport
			local result = report()
			for _, entry in snapshot() do
				-- Waehrend vorheriger Speicherungen gegangene Spieler ueberspringen.
				if entries[entry.ctx.userId] == entry then
					local ok, err = store:save(entry.ctx, entry.profile)
					if ok then
						result.saved += 1
					else
						table.insert(result.failed, { userId = entry.ctx.userId, error = err or "?" })
					end
				end
			end
			return result
		end,

		leave = function(_self, ctx: PlayerContext): (boolean, string?)
			local userId = ctx.userId
			if loading[userId] then
				loading[userId] = false
				return true, nil
			end
			local entry = entries[userId]
			if entry == nil then
				return true, nil
			end
			entries[userId] = nil
			return store:release(entry.ctx, entry.profile)
		end,

		shutdown = function(_self): SaveReport
			local result = report()
			for userId in loading do
				loading[userId] = false
			end
			for _, entry in snapshot() do
				local ok, err = session:leave(entry.ctx)
				if ok then
					result.saved += 1
				else
					table.insert(result.failed, { userId = entry.ctx.userId, error = err or "?" })
				end
			end
			return result
		end,
	}
	return session
end

return PlayerSession
