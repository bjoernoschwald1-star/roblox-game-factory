--!strict
-- Plausibilitaet der Spielerbewegung: Die Charakterposition liest der Server, sie wird aber vom Client
-- repliziert (Network Ownership). Ein Exploit kann den Charakter also direkt zu Items oder in die Verkaufsflaeche
-- setzen. MovementGuard vergleicht aufeinanderfolgende Positionen (waagrecht; Fallen und Springen bleiben frei):
-- Ist der Weg seit der letzten Probe groesser als maxSpeed * dt + slack, gilt der Spieler fuer blockSeconds als
-- gesperrt (check liefert false; ServerRuntime gibt dann keine Position heraus, collect und sell bleiben wirkungslos).
-- Gesperrt wird ab dem Sprung; die neue Position wird Ausgangspunkt der naechsten Probe.
--
-- Ohne Position (kein Charakter) wird der Ausgangspunkt verworfen; ein neuer Charakter (anderes token, z. B.
-- nach dem Respawn) beginnt ohne Vergleich. Damit lange Pausen zwischen zwei Proben nicht beliebig weite Spruenge
-- erlauben, ruft ServerRuntime check zusaetzlich im festen Takt auf. Reine Logik, Uhr kommt von aussen.
local MovementGuard = {}

export type Options = {
	maxSpeed: number?, -- Studs pro Sekunde (Standard 40; Laufen 16)
	slack: number?, -- Studs Spielraum je Probe (Standard 6; Netzwerk-Schwankungen)
	blockSeconds: number?, -- Sperre nach einem Sprung (Standard 3)
}

export type MovementGuard = {
	check: (self: MovementGuard, key: number, position: Vector3?, token: any, now: number) -> boolean,
	blocked: (self: MovementGuard, key: number, now: number) -> boolean,
	forget: (self: MovementGuard, key: number) -> (),
}

type State = {
	position: Vector3?,
	at: number,
	token: any,
	blockedUntil: number,
}

MovementGuard.DEFAULTS = table.freeze({ maxSpeed = 40, slack = 6, blockSeconds = 3 })

function MovementGuard.new(options: Options?): MovementGuard
	local opts: Options = options or {}
	local maxSpeed = opts.maxSpeed or MovementGuard.DEFAULTS.maxSpeed
	local slack = opts.slack or MovementGuard.DEFAULTS.slack
	local blockSeconds = opts.blockSeconds or MovementGuard.DEFAULTS.blockSeconds
	assert(maxSpeed > 0 and slack >= 0 and blockSeconds >= 0, "MovementGuard: invalid options")
	local states: { [number]: State } = {}

	local guard: MovementGuard = {
		check = function(_self, key: number, position: Vector3?, token: any, now: number): boolean
			local state = states[key]
			if state == nil then
				state = { position = nil, at = now, token = token, blockedUntil = -math.huge }
				states[key] = state
			end
			if position == nil then
				state.position = nil
				return false
			end
			local previous = state.position
			if previous ~= nil and state.token == token then
				local dt = math.max(now - state.at, 0)
				local offset = position - previous
				local distance = Vector2.new(offset.X, offset.Z).Magnitude
				if distance > maxSpeed * dt + slack then
					state.blockedUntil = now + blockSeconds
				end
			end
			state.position = position
			state.at = now
			state.token = token
			return now >= state.blockedUntil
		end,

		blocked = function(_self, key: number, now: number): boolean
			local state = states[key]
			return state ~= nil and now < state.blockedUntil
		end,

		forget = function(_self, key: number)
			states[key] = nil
		end,
	}
	return guard
end

return MovementGuard
