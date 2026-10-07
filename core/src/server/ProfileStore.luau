--!strict
-- Persistenzschicht fuer Spielerprofile: laden, speichern, sperren, migrieren.
--
-- Grundsatz: Ein Speicherfehler fuehrt nie dazu, dass ein vorhandener Stand ueberschrieben oder durch
-- ein Standardprofil ersetzt wird. Geschrieben wird ausschliesslich ueber storage:update (UpdateAsync),
-- und jede Schreibentscheidung faellt atomar im transform anhand des tatsaechlich gespeicherten Eintrags.
--
-- Basisfelder, die der Core in jedem Profil garantiert: schemaVersion, firstSeen, lastSeen,
-- session ({ serverId, timestamp } oder nil). Alle uebrigen Felder liefert das Game ueber defaults().
--
-- Bekannte offene Punkte:
-- - Endet load mit FAILED bei unklarem Schreibstatus, kann ein Lock bis lockTtlSeconds stehen bleiben
--   (andere Server sehen LOCKED; derselbe Server kann uebernehmen).
-- - PlayerSession.shutdown gibt nacheinander frei; die spaetere BindToClose-Anbindung muss parallel
--   freigeben (30-Sekunden-Limit).
local TableCopy = require(script.Parent.Parent.shared.TableCopy)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)
local StorageAdapter = require(script.Parent.Storage.StorageAdapter)

type PlayerContext = PlayerContext.PlayerContext

export type Profile = { [string]: any }

export type LoadState = "NEW" | "LOADED" | "LOCKED" | "FAILED" | "FUTURE_VERSION"

export type LoadResult = {
	state: LoadState,
	profile: Profile?,
	error: string?,
}

export type RetryOptions = {
	attempts: number, -- Gesamtzahl der Versuche je Speicheraufruf (mindestens 1)
	baseDelaySeconds: number, -- Abstand vor dem 2. Versuch; verdoppelt sich je weiterem Versuch
}

export type LockWaitOptions = {
	attempts: number, -- wie oft bei frischem fremdem Lock gewartet und erneut versucht wird
	delaySeconds: number,
}

export type Options = {
	storage: StorageAdapter.StorageAdapter,
	keyPrefix: string,
	defaults: () -> Profile,
	schemaVersion: number,
	migrations: { [number]: (profile: Profile) -> Profile }?, -- Schluessel n: von Version n nach n + 1
	lockTtlSeconds: number?,
	lockWait: LockWaitOptions?,
	retry: RetryOptions?,
	serverId: string,
	clock: (() -> number)?,
	sleep: ((seconds: number) -> ())?,
}

export type ProfileStore = {
	load: (self: ProfileStore, ctx: PlayerContext) -> LoadResult,
	save: (self: ProfileStore, ctx: PlayerContext, profile: Profile) -> (boolean, string?),
	release: (self: ProfileStore, ctx: PlayerContext, profile: Profile) -> (boolean, string?),
}

local DEFAULT_LOCK_TTL_SECONDS = 600
local DEFAULT_LOCK_WAIT: LockWaitOptions = { attempts = 3, delaySeconds = 5 }
local DEFAULT_RETRY: RetryOptions = { attempts = 3, baseDelaySeconds = 1 }

-- Fehlercodes von save/release (zweiter Rueckgabewert).
local LOCK_LOST = "LOCK_LOST"

local ProfileStore = {}

ProfileStore.State = table.freeze({
	NEW = "NEW" :: LoadState,
	LOADED = "LOADED" :: LoadState,
	LOCKED = "LOCKED" :: LoadState,
	FAILED = "FAILED" :: LoadState,
	FUTURE_VERSION = "FUTURE_VERSION" :: LoadState,
})

ProfileStore.LOCK_LOST = LOCK_LOST

local State = ProfileStore.State

local function storageError(err: any): string
	return "STORAGE_ERROR: " .. tostring(err)
end

function ProfileStore.new(options: Options): ProfileStore
	assert(type(options.keyPrefix) == "string", "ProfileStore: keyPrefix must be a string")
	assert(type(options.defaults) == "function", "ProfileStore: defaults must be a function")
	assert(
		type(options.schemaVersion) == "number" and options.schemaVersion >= 1,
		"ProfileStore: invalid schemaVersion"
	)
	assert(type(options.serverId) == "string" and options.serverId ~= "", "ProfileStore: serverId must be set")

	local storage = options.storage
	local keyPrefix = options.keyPrefix
	local schemaVersion = options.schemaVersion
	local serverId = options.serverId
	local migrations = options.migrations or {}
	local lockTtlSeconds = options.lockTtlSeconds or DEFAULT_LOCK_TTL_SECONDS
	local lockWait = options.lockWait or DEFAULT_LOCK_WAIT
	local retry = options.retry or DEFAULT_RETRY
	local clock: () -> number = options.clock or os.time
	local sleep: (number) -> () = options.sleep or function(seconds: number)
		task.wait(seconds)
	end

	local function keyFor(ctx: PlayerContext): string
		local userId = ctx.userId
		assert(type(userId) == "number" and userId == math.floor(userId), "ProfileStore: ctx.userId must be an integer")
		return keyPrefix .. string.format("%d", userId)
	end

	-- Fuehrt einen Speicheraufruf aus und wiederholt ihn bei Fehlern mit wachsendem Abstand.
	local function withRetry(call: () -> (boolean, any)): (boolean, any)
		local ok, result = call()
		local attempt = 1
		while not ok and attempt < retry.attempts do
			sleep(retry.baseDelaySeconds * 2 ^ (attempt - 1))
			attempt += 1
			ok, result = call()
		end
		return ok, result
	end

	local function ownsLock(entry: any): boolean
		return type(entry) == "table" and type(entry.session) == "table" and entry.session.serverId == serverId
	end

	local function foreignLockActive(entry: any, now: number): boolean
		local session = entry.session
		if type(session) ~= "table" or session.serverId == serverId then
			return false
		end
		-- Ein Lock ohne gueltigen Zeitstempel gilt als veraltet.
		return type(session.timestamp) == "number" and now - session.timestamp < lockTtlSeconds
	end

	-- Prueft einen gespeicherten Eintrag. nil = das Profil darf von diesem Server uebernommen werden.
	local function blocker(entry: any, now: number): (LoadState?, string?)
		if entry == nil then
			return nil, nil
		end
		if type(entry) ~= "table" or type(entry.schemaVersion) ~= "number" then
			return State.FAILED, "INVALID_ENTRY"
		end
		if entry.schemaVersion > schemaVersion then
			return State.FUTURE_VERSION, nil
		end
		if foreignLockActive(entry, now) then
			return State.LOCKED, nil
		end
		return nil, nil
	end

	-- Hebt ein Profil schrittweise von seiner gespeicherten Version auf schemaVersion.
	local function migrate(profile: Profile): (Profile?, string?)
		local version: number = profile.schemaVersion
		while version < schemaVersion do
			local step = migrations[version]
			if step == nil then
				return nil, string.format("MIGRATION_MISSING: %d -> %d", version, version + 1)
			end
			local ok, migrated = pcall(step, profile)
			if not ok or type(migrated) ~= "table" then
				return nil, string.format("MIGRATION_ERROR: %d -> %d: %s", version, version + 1, tostring(migrated))
			end
			version += 1
			profile = migrated
			profile.schemaVersion = version
		end
		return profile, nil
	end

	local function load(_self: ProfileStore, ctx: PlayerContext): LoadResult
		local key = keyFor(ctx)
		local waits = 0
		while true do
			local readOk, entry = withRetry(function()
				return storage:read(key)
			end)
			if not readOk then
				return { state = State.FAILED, error = storageError(entry) }
			end

			local state, err = blocker(entry, clock())
			if state == nil then
				-- Atomar uebernehmen: Der Eintrag kann sich seit dem Lesen geaendert haben.
				local outcome: LoadState? = nil
				local outcomeError: string? = nil
				local loaded: Profile? = nil
				local created = false
				local updateOk, updateErr = withRetry(function()
					return storage:update(key, function(old: any): any
						local now = clock()
						outcome, outcomeError, loaded = blocker(old, now)
						if outcome ~= nil then
							return nil
						end
						local profile: Profile
						if old == nil then
							profile = TableCopy.copy(options.defaults())
							profile.schemaVersion = schemaVersion
							profile.firstSeen = now
							created = true
							outcome = State.NEW
						else
							local migrated, migrateErr = migrate(TableCopy.copy(old))
							if migrated == nil then
								outcome, outcomeError = State.FAILED, migrateErr
								return nil
							end
							profile = migrated
							-- Wurde der Eintrag in einem vorigen Versuch dieses Aufrufs angelegt (Write-Status
							-- unbekannt), bleibt es beim Zustand NEW.
							outcome = if created and ownsLock(old) then State.NEW else State.LOADED
						end
						profile.lastSeen = now
						profile.session = { serverId = serverId, timestamp = now }
						loaded = profile
						return TableCopy.copy(profile)
					end)
				end)
				if not updateOk then
					return { state = State.FAILED, error = storageError(updateErr) }
				end
				if outcome == nil then
					return { state = State.FAILED, error = "UPDATE_WITHOUT_TRANSFORM" }
				end
				if loaded ~= nil then
					return { state = outcome, profile = loaded }
				end
				state, err = outcome, outcomeError
			end

			if state == State.LOCKED and waits < lockWait.attempts then
				waits += 1
				sleep(lockWait.delaySeconds)
			else
				return { state = state :: LoadState, error = err }
			end
		end
	end

	-- Schreibt das Profil nur, wenn der gespeicherte Lock diesem Server gehoert.
	-- keepLock = true erneuert den Lock, false gibt ihn frei.
	local function writeOwned(ctx: PlayerContext, profile: Profile, keepLock: boolean): (boolean, string?)
		local key = keyFor(ctx)
		local lockLost = false
		local released = false
		local stamp = 0
		local ok, err = withRetry(function()
			return storage:update(key, function(old: any): any
				lockLost = false
				if not keepLock and released and type(old) == "table" and old.session == nil then
					-- Ein voriger Versuch hat die Freigabe bereits geschrieben (Write-Status unbekannt).
					return nil
				end
				if not ownsLock(old) then
					lockLost = true
					return nil
				end
				local now = clock()
				local snapshot = TableCopy.copy(profile)
				snapshot.schemaVersion = schemaVersion
				snapshot.firstSeen = old.firstSeen
				snapshot.lastSeen = now
				snapshot.session = if keepLock then { serverId = serverId, timestamp = now } else nil
				stamp = now
				released = not keepLock
				return snapshot
			end)
		end)
		if not ok then
			return false, storageError(err)
		end
		if lockLost then
			return false, LOCK_LOST
		end
		profile.lastSeen = stamp
		profile.session = if keepLock then { serverId = serverId, timestamp = stamp } else nil
		return true, nil
	end

	local store: ProfileStore = {
		load = load,
		save = function(_self, ctx: PlayerContext, profile: Profile): (boolean, string?)
			return writeOwned(ctx, profile, true)
		end,
		release = function(_self, ctx: PlayerContext, profile: Profile): (boolean, string?)
			return writeOwned(ctx, profile, false)
		end,
	}
	return store
end

return ProfileStore
