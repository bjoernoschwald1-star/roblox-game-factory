--!strict
-- Gedrosselte Warnungen: gleiche key hoechstens einmal pro intervalSeconds. Unterdrueckte Meldungen werden
-- gezaehlt und beim naechsten Ausgeben als "(+N suppressed)" angehaengt. sink ist standardmaessig warn.

export type Options = {
	clock: (() -> number)?,
	intervalSeconds: number?,
	sink: ((message: string) -> ())?,
}

export type Log = {
	warnThrottled: (self: Log, key: string, message: string) -> (),
}

type KeyState = {
	lastAt: number,
	suppressed: number,
}

local DEFAULT_INTERVAL_SECONDS = 60

local Log = {}

function Log.new(options: Options?): Log
	local config: Options = options or {}
	local intervalSeconds = config.intervalSeconds or DEFAULT_INTERVAL_SECONDS
	assert(type(intervalSeconds) == "number" and intervalSeconds >= 0, "Log: intervalSeconds must be >= 0")
	local clock: () -> number = config.clock or function()
		return DateTime.now().UnixTimestampMillis / 1000
	end
	local sink: (string) -> () = config.sink or function(message: string)
		warn(message)
	end
	local states: { [string]: KeyState } = {}

	local log: Log = {
		warnThrottled = function(_self, key: string, message: string)
			local now = clock()
			local state = states[key]
			if state ~= nil and now - state.lastAt < intervalSeconds then
				state.suppressed += 1
				return
			end
			local suppressed = if state ~= nil then state.suppressed else 0
			states[key] = { lastAt = now, suppressed = 0 }
			if suppressed > 0 then
				message = string.format("%s (+%d suppressed)", message, suppressed)
			end
			sink(message)
		end,
	}
	return log
end

return Log
