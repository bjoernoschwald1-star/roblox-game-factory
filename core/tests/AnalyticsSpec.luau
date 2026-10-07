--!strict
-- Tests 56-58: feste Analytics-Events, einmalige Schritte, Feldpruefung.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local ProfileStore = require(FactoryCore.server.ProfileStore)
local PlayerSession = require(FactoryCore.server.PlayerSession)
local Analytics = require(FactoryCore.server.Analytics)
local Log = require(FactoryCore.shared.Log)

local CTX = { userId = 101 }

type Sent = { name: string, fields: { [string]: any } }

type Env = {
	now: number,
	sent: { Sent },
	sinkFails: boolean,
	warnings: { string },
	profiles: { [number]: { [string]: any } },
}

local function newEnv(): Env
	local env = {} :: Env
	env.now = 0
	env.sent = {}
	env.sinkFails = false
	env.warnings = {}
	env.profiles = { [CTX.userId] = {} }
	return env
end

local function newAnalytics(
	env: Env,
	getProfile: ((ctx: { userId: number }) -> { [string]: any }?)?
): Analytics.Analytics
	local function clock()
		return env.now
	end
	return Analytics.new({
		gameId = "game_test",
		configVersion = "1.0.0",
		getProfile = getProfile or function(ctx)
			return env.profiles[ctx.userId]
		end,
		sink = function(name: string, fields)
			if env.sinkFails then
				error("analytics service down")
			end
			table.insert(env.sent, { name = name, fields = fields })
		end,
		clock = clock,
		log = Log.new({
			clock = clock,
			sink = function(message: string)
				table.insert(env.warnings, message)
			end,
		}),
	})
end

local function newStore(memory: MemoryAdapter.MemoryAdapter, serverId: string): ProfileStore.ProfileStore
	return ProfileStore.new({
		storage = memory,
		keyPrefix = "profile_",
		defaults = function()
			return {}
		end,
		schemaVersion = 1,
		serverId = serverId,
		clock = function()
			return 1000
		end,
		sleep = function() end,
	})
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("analytics", function()
		t.it("56 session_start/session_end carry gameId, configVersion, userId, source, durationSeconds", function()
			local env = newEnv()
			local analytics = newAnalytics(env)

			t.expect(analytics:sessionStart(CTX, "paid")).toBe(true)
			env.now = 125.7
			t.expect(analytics:sessionEnd(CTX)).toBe(true)
			t.expect(env.sent).toEqual({
				{
					name = "session_start",
					fields = {
						gameId = "game_test",
						configVersion = "1.0.0",
						userId = 101,
						source = "paid",
						funnelStep = 1,
						firstSession = true,
					},
				},
				{
					name = "session_end",
					fields = { gameId = "game_test", configVersion = "1.0.0", userId = 101, durationSeconds = 125 },
				},
			})

			analytics:sessionStart(CTX, "bogus")
			t.expect(env.sent[3].fields.source).toBe("unknown")
			t.expect(#env.warnings).toBe(1)
			local ok, err = analytics:sessionEnd({ userId = 999 })
			t.expect({ ok, err }).toEqual({ false, "NO_SESSION" })
		end)

		t.it("57 step: first_collect sent once, also after reload; failing sink sets no status", function()
			local env = newEnv()
			local memory = MemoryAdapter.new()
			local sessionA = PlayerSession.new({ store = newStore(memory, "server-a"), onLoadFailed = function() end })
			sessionA:join(CTX)
			local analyticsA = newAnalytics(env, function(ctx)
				return sessionA:get(ctx)
			end)

			t.expect(analyticsA:step(CTX, "first_collect")).toBe(true)
			local again, againErr = analyticsA:step(CTX, "first_collect")
			t.expect({ again, againErr }).toEqual({ false, "ALREADY_DONE" })
			t.expect(#env.sent).toBe(1)
			t.expect(env.sent[1].fields.funnelStep).toBe(2)
			sessionA:leave(CTX)

			local sessionB = PlayerSession.new({ store = newStore(memory, "server-b"), onLoadFailed = function() end })
			t.expect(sessionB:join(CTX).state).toBe("LOADED")
			local analyticsB = newAnalytics(env, function(ctx)
				return sessionB:get(ctx)
			end)
			local reloaded, reloadedErr = analyticsB:step(CTX, "first_collect")
			t.expect({ reloaded, reloadedErr }).toEqual({ false, "ALREADY_DONE" })
			t.expect(#env.sent).toBe(1)

			env.sinkFails = true
			local failed, failedErr = analyticsB:step(CTX, "first_sell")
			t.expect({ failed, failedErr }).toEqual({ false, "SINK_ERROR" })
			t.expect((sessionB:get(CTX) :: { [string]: any }).funnel.first_sell).toBe(nil)
			env.sinkFails = false
			t.expect(analyticsB:step(CTX, "first_sell")).toBe(true)
			t.expect(env.sent[2].name).toBe("first_sell")
			t.expect(env.sent[2].fields.funnelStep).toBe(3)

			env.profiles[CTX.userId].funnel = "broken"
			local corrupt, corruptErr = newAnalytics(env):step(CTX, "first_upgrade")
			t.expect({ corrupt, corruptErr }).toEqual({ false, "CORRUPT_VALUE" })
		end)

		t.it("58 track rejects missing zoneIndex/role, price field, table values and unknown events", function()
			local env = newEnv()
			local analytics = newAnalytics(env)
			local function rejected(name: string, fields: { [string]: any }?): string?
				local ok, err = analytics:track(CTX, name, fields)
				return if ok then "SENT" else err
			end

			t.expect(rejected("zone_unlock", nil)).toBe("INVALID_FIELD")
			t.expect(rejected("zone_unlock", { zoneIndex = 0 })).toBe("INVALID_FIELD")
			t.expect(rejected("zone_unlock", { zoneIndex = 1.5 })).toBe("INVALID_FIELD")
			t.expect(rejected("purchase_success", {})).toBe("INVALID_FIELD")
			t.expect(rejected("purchase_success", { role = "coins_small", price = 99 })).toBe("INVALID_FIELD")
			t.expect(rejected("purchase_attempt", { role = "coins_small", details = {} })).toBe("INVALID_FIELD")
			t.expect(rejected("purchase_attempt", { userId = 5 })).toBe("INVALID_FIELD")
			t.expect(rejected("inventory_full", { ratio = 0 / 0 })).toBe("INVALID_FIELD")
			t.expect(rejected("level_up", {})).toBe("UNKNOWN_EVENT")
			t.expect(rejected("first_collect", {})).toBe("INVALID_KIND")
			t.expect(#env.sent).toBe(0)

			t.expect(rejected("zone_unlock", { zoneIndex = 2 })).toBe("SENT")
			t.expect(env.sent[1].fields.funnelStep).toBe(5)
			t.expect(rejected("purchase_success", { role = "coins_small" })).toBe("SENT")
			t.expect(env.sent[2].fields).toEqual({
				gameId = "game_test",
				configVersion = "1.0.0",
				userId = 101,
				role = "coins_small",
			})
		end)

		t.it("91 session_start carries funnelStep 1 and firstSession only in the first session of a player", function()
			local env = newEnv()
			local memory = MemoryAdapter.new()
			local sessionA = PlayerSession.new({ store = newStore(memory, "server-a"), onLoadFailed = function() end })
			sessionA:join(CTX)
			local analyticsA = newAnalytics(env, function(ctx)
				return sessionA:get(ctx)
			end)
			t.expect(analyticsA:sessionStart(CTX, "organic")).toBe(true)
			t.expect({ env.sent[1].fields.funnelStep, env.sent[1].fields.firstSession }).toEqual({ 1, true })
			sessionA:leave(CTX)

			local sessionB = PlayerSession.new({ store = newStore(memory, "server-b"), onLoadFailed = function() end })
			t.expect(sessionB:join(CTX).state).toBe("LOADED")
			local analyticsB = newAnalytics(env, function(ctx)
				return sessionB:get(ctx)
			end)
			t.expect(analyticsB:sessionStart(CTX, "organic")).toBe(true)
			t.expect(env.sent[2].fields).toEqual({
				gameId = "game_test",
				configVersion = "1.0.0",
				userId = 101,
				source = "organic",
			})

			-- Werfender sink bei der ersten Sitzung: Status bleibt offen, die naechste Sitzung sendet Schritt 1.
			local other = { userId = 202 }
			env.profiles[202] = {}
			local analytics = newAnalytics(env)
			env.sinkFails = true
			local failed, failedErr = analytics:sessionStart(other, "paid")
			t.expect({ failed, failedErr }).toEqual({ false, "SINK_ERROR" })
			t.expect(env.profiles[202].funnel.session_start).toBe(nil)
			env.sinkFails = false
			t.expect(analytics:sessionStart(other, "paid")).toBe(true)
			local retried = env.sent[#env.sent].fields
			t.expect({ retried.userId, retried.funnelStep, retried.firstSession }).toEqual({ 202, 1, true })

			-- Beschaedigtes Funnel-Feld: session_start trotzdem, aber ohne funnelStep; Feld bleibt, Warnung.
			env.profiles[CTX.userId].funnel = "broken"
			local warningsBefore = #env.warnings
			t.expect(analytics:sessionStart(CTX, "paid")).toBe(true)
			local corrupt = env.sent[#env.sent].fields
			t.expect({ corrupt.userId, corrupt.funnelStep, corrupt.firstSession }).toEqual({ 101 })
			t.expect(env.profiles[CTX.userId].funnel).toBe("broken")
			t.expect(#env.warnings).toBe(warningsBefore + 1)
		end)
	end)
end
