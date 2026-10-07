--!strict
-- Feste, theme-neutrale Events, identisch fuer alle Games. sink ist spaeter der Wrapper um Roblox' Analytics-
-- Funktionen; jedes Event traegt gameId, configVersion und userId.
--
-- Events: session_start (source: paid | organic | unknown), session_end (durationSeconds), tutorial_start,
-- tutorial_complete, first_collect, inventory_full, first_sell, first_upgrade, zone_unlock (zoneIndex),
-- purchase_attempt, purchase_success (role; nie ein Preis).
-- Funnel: session_start -> first_collect -> first_sell -> first_upgrade -> zone_unlock(zoneIndex 2); Events auf
-- dem Funnel bekommen zusaetzlich funnelStep (1-5).
--
-- step(): einmal im Leben pro Spieler, Status im Profil (profile[field] = { [eventName]: true }). sink laeuft in
-- pcall; schlaegt er fehl, gilt das Event als nicht gesendet und der step-Status wird nicht gesetzt.
--
-- Fehlercodes: UNKNOWN_EVENT, INVALID_KIND (Event gehoert zu einer anderen Funktion), INVALID_FIELD,
-- NO_SESSION, NOT_LOADED, CORRUPT_VALUE, ALREADY_DONE, SINK_ERROR.
local Log = require(script.Parent.Parent.shared.Log)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)

type PlayerContext = PlayerContext.PlayerContext
type Profile = { [string]: any }

export type FieldValue = string | number | boolean
export type Fields = { [string]: FieldValue }

export type Options = {
	gameId: string,
	configVersion: string,
	getProfile: (ctx: PlayerContext) -> Profile?,
	sink: (eventName: string, fields: Fields) -> (),
	field: string?,
	clock: (() -> number)?,
	log: Log.Log?,
}

export type Analytics = {
	sessionStart: (self: Analytics, ctx: PlayerContext, source: string) -> (boolean, string?),
	sessionEnd: (self: Analytics, ctx: PlayerContext) -> (boolean, string?),
	step: (self: Analytics, ctx: PlayerContext, name: string) -> (boolean, string?),
	track: (self: Analytics, ctx: PlayerContext, name: string, fields: { [string]: any }?) -> (boolean, string?),
}

local KIND: { [string]: string } = {
	session_start = "session",
	session_end = "session",
	tutorial_start = "step",
	tutorial_complete = "step",
	first_collect = "step",
	first_sell = "step",
	first_upgrade = "step",
	inventory_full = "track",
	zone_unlock = "track",
	purchase_attempt = "track",
	purchase_success = "track",
}

local FUNNEL_STEP: { [string]: number } = {
	session_start = 1,
	first_collect = 2,
	first_sell = 3,
	first_upgrade = 4,
}
local FUNNEL_ZONE_INDEX = 2
local FUNNEL_ZONE_STEP = 5

local SOURCES = { paid = true, organic = true, unknown = true }
local RESERVED = { gameId = true, configVersion = true, userId = true, funnelStep = true, price = true }
local DEFAULT_FIELD = "funnel"

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local Analytics = {}

Analytics.FUNNEL = table.freeze({ "session_start", "first_collect", "first_sell", "first_upgrade", "zone_unlock" })

function Analytics.new(options: Options): Analytics
	assert(type(options.gameId) == "string" and options.gameId ~= "", "Analytics: gameId must be set")
	assert(type(options.configVersion) == "string" and options.configVersion ~= "", "Analytics: configVersion")
	assert(type(options.getProfile) == "function", "Analytics: getProfile must be a function")
	assert(type(options.sink) == "function", "Analytics: sink must be a function")
	local field = options.field or DEFAULT_FIELD
	local gameId = options.gameId
	local configVersion = options.configVersion
	local getProfile = options.getProfile
	local sink = options.sink
	local clock: () -> number = options.clock or function()
		return DateTime.now().UnixTimestampMillis / 1000
	end
	local log = options.log or Log.new({ clock = clock })

	local sessionStarts: { [number]: number } = {}

	-- Prueft frei uebergebene Felder: nur string, endliche Zahl oder boolean; reservierte Namen und "price"
	-- sind verboten.
	local function cleanFields(fields: { [string]: any }?): Fields?
		local clean: Fields = {}
		for name, value in fields or {} do
			if type(name) ~= "string" or name == "" or RESERVED[name] then
				return nil
			end
			if type(value) == "string" or type(value) == "boolean" or isFinite(value) then
				clean[name] = value
			else
				return nil
			end
		end
		return clean
	end

	local function send(ctx: PlayerContext, name: string, fields: Fields): (boolean, string?)
		local payload: Fields = table.clone(fields)
		payload.gameId = gameId
		payload.configVersion = configVersion
		payload.userId = ctx.userId
		local funnelStep = FUNNEL_STEP[name]
		if name == "zone_unlock" and payload.zoneIndex == FUNNEL_ZONE_INDEX then
			funnelStep = FUNNEL_ZONE_STEP
		end
		if funnelStep ~= nil then
			payload.funnelStep = funnelStep
		end
		local ok, err = pcall(sink, name, payload)
		if not ok then
			log:warnThrottled("sink", "[Analytics] sink failed: " .. tostring(err))
			return false, "SINK_ERROR"
		end
		return true, nil
	end

	local function checkKind(name: string, kind: string): string?
		local actual = KIND[name]
		if actual == nil then
			return "UNKNOWN_EVENT"
		end
		if actual ~= kind then
			return "INVALID_KIND"
		end
		return nil
	end

	-- Set der erledigten Schritte; fehlendes Feld wird angelegt. nil = vorhandener Wert ungueltig.
	local function doneSteps(profile: Profile): { [string]: boolean }?
		local stored = profile[field]
		if stored == nil then
			stored = {}
			profile[field] = stored
			return stored
		end
		if type(stored) ~= "table" then
			return nil
		end
		for name, value in stored do
			if type(name) ~= "string" or value ~= true then
				return nil
			end
		end
		return stored
	end

	local analytics: Analytics = {
		sessionStart = function(_self, ctx: PlayerContext, source: string): (boolean, string?)
			if type(source) ~= "string" or not SOURCES[source] then
				log:warnThrottled(
					"source",
					"[Analytics] invalid session source " .. tostring(source) .. ", using unknown"
				)
				source = "unknown"
			end
			sessionStarts[ctx.userId] = clock()
			return send(ctx, "session_start", { source = source })
		end,

		sessionEnd = function(_self, ctx: PlayerContext): (boolean, string?)
			local startedAt = sessionStarts[ctx.userId]
			if startedAt == nil then
				return false, "NO_SESSION"
			end
			sessionStarts[ctx.userId] = nil
			local duration = math.max(0, math.floor(clock() - startedAt))
			return send(ctx, "session_end", { durationSeconds = duration })
		end,

		step = function(_self, ctx: PlayerContext, name: string): (boolean, string?)
			local kindErr = checkKind(name, "step")
			if kindErr then
				return false, kindErr
			end
			local profile = getProfile(ctx)
			if profile == nil then
				return false, "NOT_LOADED"
			end
			local done = doneSteps(profile)
			if done == nil then
				return false, "CORRUPT_VALUE"
			end
			if done[name] then
				return false, "ALREADY_DONE"
			end
			local sent, err = send(ctx, name, {})
			if sent then
				done[name] = true
			end
			return sent, err
		end,

		track = function(_self, ctx: PlayerContext, name: string, fields: { [string]: any }?): (boolean, string?)
			local kindErr = checkKind(name, "track")
			if kindErr then
				return false, kindErr
			end
			local clean = cleanFields(fields)
			if clean == nil then
				return false, "INVALID_FIELD"
			end
			if name == "zone_unlock" then
				local zoneIndex = clean.zoneIndex
				if
					not (
						isFinite(zoneIndex)
						and (zoneIndex :: number) >= 1
						and zoneIndex == math.floor(zoneIndex :: number)
					)
				then
					return false, "INVALID_FIELD"
				end
			elseif name == "purchase_success" then
				if type(clean.role) ~= "string" or clean.role == "" then
					return false, "INVALID_FIELD"
				end
			end
			return send(ctx, name, clean)
		end,
	}
	return analytics
end

return Analytics
