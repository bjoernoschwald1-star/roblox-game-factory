--!strict
-- Tests 1-12: ProfileStore und PlayerSession mit MemoryAdapter, Fake-Kontext, injizierter Uhr und sleep ohne Warten.
local ServerScriptService = game:GetService("ServerScriptService")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local ProfileStore = require(FactoryCore.server.ProfileStore)
local PlayerSession = require(FactoryCore.server.PlayerSession)

local CTX = { userId = 101 }
local KEY = "profile_101"
local START = 1000

type Env = {
	memory: MemoryAdapter.MemoryAdapter,
	now: number,
	sleeps: { number },
	store: (serverId: string, overrides: { [string]: any }?) -> ProfileStore.ProfileStore,
}

local function defaults(): ProfileStore.Profile
	return { points = 0, flags = {} }
end

local function newEnv(): Env
	local env = {} :: Env
	env.memory = MemoryAdapter.new()
	env.now = START
	env.sleeps = {}
	env.store = function(serverId: string, overrides: { [string]: any }?): ProfileStore.ProfileStore
		local options: { [string]: any } = {
			storage = env.memory,
			keyPrefix = "profile_",
			defaults = defaults,
			schemaVersion = 1,
			lockTtlSeconds = 60,
			lockWait = { attempts = 2, delaySeconds = 5 },
			retry = { attempts = 3, baseDelaySeconds = 1 },
			serverId = serverId,
			clock = function()
				return env.now
			end,
			sleep = function(seconds: number)
				table.insert(env.sleeps, seconds)
				env.now += seconds
			end,
		}
		for name, value in overrides or {} do
			options[name] = value
		end
		return ProfileStore.new(options :: any)
	end
	return env
end

local function storedEntry(values: { [string]: any }): { [string]: any }
	local entry: { [string]: any } =
		{ schemaVersion = 1, firstSeen = 500, lastSeen = 600, points = 42, flags = { a = true } }
	for name, value in values do
		entry[name] = value
	end
	return entry
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("profile store", function()
		t.it("01 new player: NEW with defaults and base fields, stored, locked by this server", function()
			local env = newEnv()
			local result = env.store("server-a"):load(CTX)

			t.expect(result.state).toBe("NEW")
			t.expect(result.profile).toEqual({
				points = 0,
				flags = {},
				schemaVersion = 1,
				firstSeen = START,
				lastSeen = START,
				session = { serverId = "server-a", timestamp = START },
			})
			t.expect(env.memory:peek(KEY)).toEqual(result.profile)
			t.expect(env.memory.stats.writes).toBe(1)
		end)

		t.it("02 existing player: LOADED with unchanged values", function()
			local env = newEnv()
			env.memory:seed(KEY, storedEntry({}))
			local result = env.store("server-a"):load(CTX)

			t.expect(result.state).toBe("LOADED")
			local profile = result.profile :: ProfileStore.Profile
			t.expect(profile.points).toBe(42)
			t.expect(profile.flags).toEqual({ a = true })
			t.expect(profile.firstSeen).toBe(500)
			t.expect(profile.schemaVersion).toBe(1)
			t.expect(profile.session).toEqual({ serverId = "server-a", timestamp = START })
		end)

		t.it("03 save, release via session, reload on a second server returns the same state", function()
			local env = newEnv()
			local failures = {}
			local sessionA = PlayerSession.new({
				store = env.store("server-a"),
				onLoadFailed = function(_, state)
					table.insert(failures, state)
				end,
			})
			t.expect(sessionA:join(CTX).state).toBe("NEW")
			local profile = sessionA:get(CTX) :: ProfileStore.Profile
			profile.points = 7
			profile.flags.x = true

			t.expect(sessionA:autosaveAll()).toEqual({ saved = 1, failed = {} })
			t.expect(env.memory:peek(KEY).points).toBe(7)
			t.expect(sessionA:leave(CTX)).toBe(true)
			t.expect(sessionA:get(CTX)).toBe(nil)

			local result = env.store("server-b"):load(CTX)
			t.expect(result.state).toBe("LOADED")
			local reloaded = result.profile :: ProfileStore.Profile
			t.expect(reloaded.points).toBe(7)
			t.expect(reloaded.flags).toEqual({ x = true })
			t.expect(reloaded.firstSeen).toBe(START)
			t.expect(reloaded.session.serverId).toBe("server-b")
			t.expect(#failures).toBe(0)
		end)

		t.it("04 read failing on every attempt: FAILED, nothing written, no default profile", function()
			local env = newEnv()
			env.memory:failReads(3)
			local failures = {}
			local session = PlayerSession.new({
				store = env.store("server-a"),
				onLoadFailed = function(ctx, state)
					table.insert(failures, { ctx.userId, state })
				end,
			})
			local result = session:join(CTX)

			t.expect(result.state).toBe("FAILED")
			t.expect(result.profile).toBe(nil)
			t.expect(env.memory:peek(KEY)).toBe(nil)
			t.expect(env.memory.stats.reads).toBe(3)
			t.expect(env.memory.stats.updates).toBe(0)
			t.expect(env.memory.stats.writes).toBe(0)
			t.expect(env.sleeps).toEqual({ 1, 2 })
			t.expect(session:get(CTX)).toBe(nil)
			t.expect(failures).toEqual({ { 101, "FAILED" } })
		end)

		t.it("05 transient storage error on save: retried, then successful", function()
			local env = newEnv()
			local store = env.store("server-a")
			local profile = store:load(CTX).profile :: ProfileStore.Profile
			profile.points = 5
			env.sleeps = {}
			-- 1. Versuch: Fehler ohne Schreiben; 2. Versuch: schreibt, meldet aber Fehler; 3. Versuch: ok.
			env.memory:failUpdates(1)
			env.memory:failUpdatesAfterWrite(1)

			local ok, err = store:save(CTX, profile)
			t.expect(ok).toBe(true)
			t.expect(err).toBe(nil)
			t.expect(env.sleeps).toEqual({ 1, 2 })
			local stored = env.memory:peek(KEY)
			t.expect(stored.points).toBe(5)
			t.expect(stored.session).toEqual({ serverId = "server-a", timestamp = START + 3 })
			t.expect(profile.lastSeen).toBe(START + 3)
		end)

		t.it("06 permanent storage error on save: error returned, no exception, stored state unchanged", function()
			local env = newEnv()
			local store = env.store("server-a")
			local profile = store:load(CTX).profile :: ProfileStore.Profile
			local before = env.memory:peek(KEY)
			profile.points = 9
			env.sleeps = {}
			env.memory:failUpdates(100)

			local called, ok, err = pcall(function()
				return store:save(CTX, profile)
			end)
			t.expect(called).toBe(true)
			t.expect(ok).toBe(false)
			t.expect(string.sub(tostring(err), 1, 14)).toBe("STORAGE_ERROR:")
			t.expect(env.sleeps).toEqual({ 1, 2 })
			t.expect(env.memory:peek(KEY)).toEqual(before)
			t.expect(profile.points).toBe(9)
		end)

		t.it("07 fresh foreign lock: LOCKED after the wait attempts, nothing overwritten", function()
			local env = newEnv()
			local entry = storedEntry({ session = { serverId = "server-b", timestamp = START } })
			env.memory:seed(KEY, entry)
			local result = env.store("server-a"):load(CTX)

			t.expect(result.state).toBe("LOCKED")
			t.expect(result.profile).toBe(nil)
			t.expect(env.sleeps).toEqual({ 5, 5 })
			t.expect(env.memory:peek(KEY)).toEqual(entry)
			t.expect(env.memory.stats.writes).toBe(0)
		end)

		t.it("08 stale foreign lock: taken over, LOADED", function()
			local env = newEnv()
			env.memory:seed(KEY, storedEntry({ session = { serverId = "server-b", timestamp = START - 61 } }))
			local result = env.store("server-a"):load(CTX)

			t.expect(result.state).toBe("LOADED")
			t.expect(env.sleeps).toEqual({})
			t.expect(env.memory:peek(KEY).session).toEqual({ serverId = "server-a", timestamp = START })
			t.expect((result.profile :: ProfileStore.Profile).points).toBe(42)
		end)

		t.it("09 save with a foreign lock in the entry: refused, entry unchanged", function()
			local env = newEnv()
			local store = env.store("server-a")
			local profile = store:load(CTX).profile :: ProfileStore.Profile
			local taken = env.memory:peek(KEY)
			taken.session = { serverId = "server-b", timestamp = START }
			env.memory:seed(KEY, taken)
			profile.points = 99

			local ok, err = store:save(CTX, profile)
			t.expect(ok).toBe(false)
			t.expect(err).toBe("LOCK_LOST")
			t.expect(env.memory:peek(KEY)).toEqual(taken)
		end)

		t.it("10 migration from version 1 to 2 is applied", function()
			local env = newEnv()
			env.memory:seed(KEY, storedEntry({ points = 3 }))
			local store = env.store("server-a", {
				schemaVersion = 2,
				migrations = {
					[1] = function(profile)
						profile.score = profile.points
						profile.points = nil
						return profile
					end,
				},
			})
			local result = store:load(CTX)

			t.expect(result.state).toBe("LOADED")
			local profile = result.profile :: ProfileStore.Profile
			t.expect(profile.schemaVersion).toBe(2)
			t.expect(profile.score).toBe(3)
			t.expect(profile.points).toBe(nil)
			t.expect(env.memory:peek(KEY).schemaVersion).toBe(2)
			t.expect(env.memory:peek(KEY).score).toBe(3)
		end)

		t.it("11 stored version newer than known: FUTURE_VERSION, nothing written", function()
			local env = newEnv()
			local entry = storedEntry({ schemaVersion = 3 })
			env.memory:seed(KEY, entry)
			local failures = {}
			local session = PlayerSession.new({
				store = env.store("server-a", { schemaVersion = 2 }),
				onLoadFailed = function(_, state)
					table.insert(failures, state)
				end,
			})
			local result = session:join(CTX)

			t.expect(result.state).toBe("FUTURE_VERSION")
			t.expect(result.profile).toBe(nil)
			t.expect(env.memory:peek(KEY)).toEqual(entry)
			t.expect(env.memory.stats.writes).toBe(0)
			t.expect(failures).toEqual({ "FUTURE_VERSION" })
			t.expect(session:get(CTX)).toBe(nil)
		end)

		t.it("12 release removes the lock (direct and via session shutdown)", function()
			local env = newEnv()
			local store = env.store("server-a")
			local profile = store:load(CTX).profile :: ProfileStore.Profile
			profile.points = 4

			t.expect(store:release(CTX, profile)).toBe(true)
			t.expect(env.memory:peek(KEY).session).toBe(nil)
			t.expect(env.memory:peek(KEY).points).toBe(4)
			t.expect(profile.session).toBe(nil)

			local session = PlayerSession.new({
				store = env.store("server-b"),
				onLoadFailed = function() end,
			})
			t.expect(session:join(CTX).state).toBe("LOADED")
			t.expect(session:join({ userId = 202 }).state).toBe("NEW")
			t.expect(env.sleeps).toEqual({})
			t.expect(session:shutdown()).toEqual({ saved = 2, failed = {} })
			t.expect(env.memory:peek(KEY).session).toBe(nil)
			t.expect(env.memory:peek("profile_202").session).toBe(nil)
			t.expect(session:get(CTX)).toBe(nil)
		end)

		t.it(
			"48 PlayerSession:save stores a single profile; NOT_LOADED without profile; LOCK_LOST passed on",
			function()
				local env = newEnv()
				local session = PlayerSession.new({
					store = env.store("server-a"),
					onLoadFailed = function() end,
				})
				session:join(CTX)
				session:join({ userId = 202 })
				local profileA = session:get(CTX) :: ProfileStore.Profile
				local profileB = session:get({ userId = 202 }) :: ProfileStore.Profile
				profileA.points = 3
				profileB.points = 8

				t.expect({ session:save(CTX) }).toEqual({ true })
				t.expect(env.memory:peek(KEY).points).toBe(3)
				-- Nur dieses eine Profil wurde gespeichert.
				t.expect(env.memory:peek("profile_202").points).toBe(0)

				local missingOk, missingErr = session:save({ userId = 999 })
				t.expect({ missingOk, missingErr }).toEqual({ false, "NOT_LOADED" })

				local taken = env.memory:peek(KEY)
				taken.session = { serverId = "server-b", timestamp = env.now }
				env.memory:seed(KEY, taken)
				local lostOk, lostErr = session:save(CTX)
				t.expect({ lostOk, lostErr }).toEqual({ false, "LOCK_LOST" })
				t.expect(env.memory:peek(KEY)).toEqual(taken)
			end
		)
	end)
end
