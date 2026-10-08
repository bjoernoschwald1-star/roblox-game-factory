--!strict
-- Client-Absichten: collect(), sell(), buyUpgrade(dimension), unlockZone(zoneId), prestige(). Eigenstaendig, ohne require auf
-- Server-Module. Es werden nie Spielwerte, Positionen oder Preise mitgeschickt; der Server entscheidet alles.
-- Die Drossel schuetzt nur gegen versehentliches Spammen (pro Absicht hoechstens alle minIntervalSeconds); die
-- verbindlichen Grenzen setzt der Server (RemoteGateway). Jede Methode liefert, ob die Absicht gesendet wurde.
-- Intents.fromRemotes(folder) nutzt die RemoteEvents im Ordner FactoryRemotes (RemoteEvent:FireServer).

export type Options = {
	fire: (name: string, ...any) -> (),
	clock: (() -> number)?,
	minIntervalSeconds: number?,
}

export type Intents = {
	collect: (self: Intents) -> boolean,
	sell: (self: Intents) -> boolean,
	buyUpgrade: (self: Intents, dimension: string) -> boolean,
	unlockZone: (self: Intents, zoneId: string) -> boolean,
	prestige: (self: Intents) -> boolean,
}

local DEFAULT_MIN_INTERVAL_SECONDS = 0.1

local function isId(value: any): boolean
	return type(value) == "string" and value ~= "" and #value <= 64
end

local Intents = {}

function Intents.new(options: Options): Intents
	assert(type(options.fire) == "function", "Intents: fire must be a function")
	local fire = options.fire
	local clock: () -> number = options.clock or os.clock
	local minInterval = options.minIntervalSeconds or DEFAULT_MIN_INTERVAL_SECONDS
	local lastSent: { [string]: number } = {}

	local function send(name: string, ...: any): boolean
		local now = clock()
		local last = lastSent[name]
		if last ~= nil and now - last < minInterval then
			return false
		end
		local ok, err = pcall(fire, name, ...)
		if not ok then
			warn("[Intents] fire failed: " .. tostring(err))
			return false
		end
		lastSent[name] = now
		return true
	end

	local intents: Intents = {
		collect = function(_self): boolean
			return send("collect")
		end,
		sell = function(_self): boolean
			return send("sell")
		end,
		buyUpgrade = function(_self, dimension: string): boolean
			return isId(dimension) and send("buyUpgrade", dimension)
		end,
		unlockZone = function(_self, zoneId: string): boolean
			return isId(zoneId) and send("unlockZone", zoneId)
		end,
		prestige = function(_self): boolean
			return send("prestige")
		end,
	}
	return intents
end

-- Fabrik fuer den echten Client: feuert die gleichnamigen RemoteEvents im Ordner (z. B. FactoryRemotes).
function Intents.fromRemotes(folder: Instance, clock: (() -> number)?): Intents
	return Intents.new({
		fire = function(name: string, ...: any)
			local remote = folder:FindFirstChild(name)
			if remote ~= nil and remote:IsA("RemoteEvent") then
				remote:FireServer(...)
			end
		end,
		clock = clock,
	})
end

return Intents
