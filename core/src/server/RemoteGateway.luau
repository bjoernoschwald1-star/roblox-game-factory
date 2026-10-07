--!strict
-- Einziger Eingang fuer Client-Anfragen. Feste, kleine Liste von Remotes (register, dann seal); jede Remote hat
-- ein Schema fuer ihre Argumente und ein Rate Limit pro Spieler. Kein anderes Modul hoert direkt auf Remotes;
-- die spaetere Anbindung leitet jedes OnServerEvent nur an dispatch weiter.
--
-- dispatch prueft in fester Reihenfolge: unbekannter Name (UNKNOWN_REMOTE), Argumentanzahl (BAD_ARGS), Schema
-- (BAD_ARGS), Rate Limit (RATE_LIMITED), Handler (HANDLER_ERROR, gedrosselt geloggt). Jede Ablehnung wird pro
-- Spieler gezaehlt und an onRejected gemeldet. Der Rueckgabewert dient nur Tests und der Anbindung; an den
-- Client geht nie eine Antwort auf abgelehnte Anfragen.
--
-- ArgSpec: { type = "string", maxLength, oneOf? } | { type = "number", min, max, integer? } | { type = "boolean" }
-- | { type = "vector3", maxMagnitude? } (alle Komponenten endlich) | { type = "id", isKnown }.
local Log = require(script.Parent.Parent.shared.Log)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)

type PlayerContext = PlayerContext.PlayerContext

export type ArgSpec = {
	type: string,
	maxLength: number?,
	oneOf: { string }?,
	min: number?,
	max: number?,
	integer: boolean?,
	maxMagnitude: number?,
	isKnown: ((id: string) -> boolean)?,
}

export type RateLimit = {
	max: number,
	windowSeconds: number,
}

export type RemoteSpec = {
	args: { ArgSpec },
	rateLimit: RateLimit,
	handler: (ctx: PlayerContext, ...any) -> (),
}

export type Options = {
	clock: (() -> number)?,
	log: Log.Log?,
	onRejected: ((ctx: PlayerContext, name: string, err: string) -> ())?,
}

export type RemoteGateway = {
	register: (self: RemoteGateway, name: string, spec: RemoteSpec) -> (),
	seal: (self: RemoteGateway) -> (),
	dispatch: (self: RemoteGateway, ctx: PlayerContext, name: string, ...any) -> (boolean, string?),
	rejectedCount: (self: RemoteGateway, ctx: PlayerContext) -> number,
	clearPlayer: (self: RemoteGateway, ctx: PlayerContext) -> (),
}

type PlayerState = {
	rejected: number,
	calls: { [string]: { number } },
}

local NAME_PATTERN = "^[a-z][%w]*$"

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function assertArgSpec(name: string, index: number, spec: ArgSpec)
	local where = string.format("RemoteGateway: %s arg %d", name, index)
	assert(type(spec) == "table", where .. ": spec must be a table")
	if spec.type == "string" then
		assert(isFinite(spec.maxLength) and (spec.maxLength :: number) >= 0, where .. ": maxLength required")
		if spec.oneOf ~= nil then
			assert(type(spec.oneOf) == "table" and #spec.oneOf > 0, where .. ": oneOf must be a non-empty list")
		end
	elseif spec.type == "number" then
		assert(isFinite(spec.min) and isFinite(spec.max), where .. ": min and max required")
		assert((spec.min :: number) <= (spec.max :: number), where .. ": min must be <= max")
	elseif spec.type == "boolean" then
		return
	elseif spec.type == "vector3" then
		assert(spec.maxMagnitude == nil or isFinite(spec.maxMagnitude), where .. ": maxMagnitude must be finite")
	elseif spec.type == "id" then
		assert(type(spec.isKnown) == "function", where .. ": isKnown required")
	else
		error(where .. ": unknown type " .. tostring(spec.type))
	end
end

-- Prueft einen einzelnen Wert gegen sein Schema.
local function matches(spec: ArgSpec, value: any): boolean
	if spec.type == "string" then
		if type(value) ~= "string" or #value > (spec.maxLength :: number) then
			return false
		end
		return spec.oneOf == nil or table.find(spec.oneOf, value) ~= nil
	elseif spec.type == "number" then
		if not isFinite(value) or value < (spec.min :: number) or value > (spec.max :: number) then
			return false
		end
		return not spec.integer or value == math.floor(value)
	elseif spec.type == "boolean" then
		return type(value) == "boolean"
	elseif spec.type == "vector3" then
		if typeof(value) ~= "Vector3" or not (isFinite(value.X) and isFinite(value.Y) and isFinite(value.Z)) then
			return false
		end
		return spec.maxMagnitude == nil or value.Magnitude <= (spec.maxMagnitude :: number)
	elseif spec.type == "id" then
		if type(value) ~= "string" or value == "" then
			return false
		end
		local ok, known = pcall(spec.isKnown :: (string) -> boolean, value)
		return ok and known == true
	end
	return false
end

local RemoteGateway = {}

function RemoteGateway.new(options: Options?): RemoteGateway
	local config: Options = options or {}
	local clock: () -> number = config.clock or function()
		return DateTime.now().UnixTimestampMillis / 1000
	end
	local log = config.log or Log.new({ clock = clock })
	local onRejected = config.onRejected

	local remotes: { [string]: RemoteSpec } = {}
	local sealed = false
	local players: { [number]: PlayerState } = {}

	local function stateOf(ctx: PlayerContext): PlayerState
		local state = players[ctx.userId]
		if state == nil then
			state = { rejected = 0, calls = {} }
			players[ctx.userId] = state
		end
		return state
	end

	local function reject(ctx: PlayerContext, name: string, err: string): (boolean, string?)
		stateOf(ctx).rejected += 1
		if onRejected then
			local ok, callbackErr = pcall(onRejected, ctx, name, err)
			if not ok then
				log:warnThrottled("onRejected", "[RemoteGateway] onRejected failed: " .. tostring(callbackErr))
			end
		end
		return false, err
	end

	local gateway: RemoteGateway = {
		register = function(_self, name: string, spec: RemoteSpec)
			assert(not sealed, "RemoteGateway: register after seal")
			assert(type(name) == "string" and string.match(name, NAME_PATTERN) ~= nil, "RemoteGateway: invalid name")
			assert(remotes[name] == nil, "RemoteGateway: " .. name .. " is already registered")
			assert(type(spec) == "table" and type(spec.args) == "table", "RemoteGateway: " .. name .. " needs args")
			for index, argSpec in spec.args do
				assertArgSpec(name, index, argSpec)
			end
			local rateLimit = spec.rateLimit
			assert(
				type(rateLimit) == "table"
					and isFinite(rateLimit.max)
					and rateLimit.max > 0
					and isFinite(rateLimit.windowSeconds)
					and rateLimit.windowSeconds > 0,
				"RemoteGateway: " .. name .. " needs a rateLimit with max > 0 and windowSeconds > 0"
			)
			assert(type(spec.handler) == "function", "RemoteGateway: " .. name .. " needs a handler")
			remotes[name] = spec
		end,

		seal = function(_self)
			sealed = true
		end,

		dispatch = function(_self, ctx: PlayerContext, name: string, ...: any): (boolean, string?)
			assert(sealed, "RemoteGateway: dispatch before seal")
			local remote = if type(name) == "string" then remotes[name] else nil
			if remote == nil then
				return reject(ctx, tostring(name), "UNKNOWN_REMOTE")
			end
			if select("#", ...) ~= #remote.args then
				return reject(ctx, name, "BAD_ARGS")
			end
			for index, argSpec in remote.args do
				if not matches(argSpec, (select(index, ...))) then
					return reject(ctx, name, "BAD_ARGS")
				end
			end

			local state = stateOf(ctx)
			local now = clock()
			local recent: { number } = {}
			for _, at in state.calls[name] or {} do
				if at > now - remote.rateLimit.windowSeconds then
					table.insert(recent, at)
				end
			end
			if #recent >= remote.rateLimit.max then
				state.calls[name] = recent
				return reject(ctx, name, "RATE_LIMITED")
			end
			table.insert(recent, now)
			state.calls[name] = recent

			local ok, err = pcall(remote.handler, ctx, ...)
			if not ok then
				log:warnThrottled(
					"handler:" .. name,
					"[RemoteGateway] handler " .. name .. " failed: " .. tostring(err)
				)
				return reject(ctx, name, "HANDLER_ERROR")
			end
			return true, nil
		end,

		rejectedCount = function(_self, ctx: PlayerContext): number
			local state = players[ctx.userId]
			return if state ~= nil then state.rejected else 0
		end,

		clearPlayer = function(_self, ctx: PlayerContext)
			players[ctx.userId] = nil
		end,
	}
	return gateway
end

return RemoteGateway
