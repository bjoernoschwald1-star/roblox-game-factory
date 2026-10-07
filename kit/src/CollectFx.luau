--!strict
-- Sog-Feedback im Client: eingesammelte Items verschwinden nicht schlagartig, sondern fliegen zum Charakter.
-- pull(part, target, color) uebernimmt den lokalen Item-Part (aus ItemView.reconcile ueber onRemove), haengt einen
-- kurzen Strahl (Beam) zwischen Part und Ziel, und update(now) bewegt ihn mit Ease-In zum Ziel und schrumpft ihn.
-- Am Ziel gibt es einen kurzen Partikelstoss (ParticleEmitter:Emit, Standard-Partikel ohne Textur-Asset), danach
-- wird der Part zerstoert. Verschwindet das Ziel, endet die Animation sofort. Rein clientseitig, aus dem
-- Schnappschuss-Diff abgeleitet; Server-Logik unveraendert. Die Uhr kommt von aussen (Test: feste Zeiten).
-- Interpolation von Hand statt TweenService, weil das Ziel (der laufende Charakter) sich waehrend des Flugs bewegt.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/Beam
--       https://create.roblox.com/docs/reference/engine/classes/ParticleEmitter#Emit

export type CollectFx = {
	pull: (self: CollectFx, part: BasePart, target: BasePart?, color: Color3?) -> boolean,
	update: (self: CollectFx, now: number) -> number,
	active: (self: CollectFx) -> number,
	destroy: (self: CollectFx) -> (),
}

export type Options = {
	clock: () -> number,
	duration: number?,
	burst: number?,
}

type Flight = {
	part: BasePart,
	target: BasePart,
	from: Vector3,
	startSize: Vector3,
	startedAt: number,
	color: Color3,
}

local DEFAULT_DURATION = 0.35
local DEFAULT_BURST = 12

local CollectFx = {}

CollectFx.DEFAULT_DURATION = DEFAULT_DURATION

-- Position auf dem Weg (Ease-In: langsam los, schnell am Ziel) fuer alpha in [0, 1].
function CollectFx.lerpPosition(from: Vector3, to: Vector3, alpha: number): Vector3
	local clamped = math.clamp(alpha, 0, 1)
	return from:Lerp(to, clamped * clamped)
end

function CollectFx.new(holder: Instance, options: Options): CollectFx
	local clock = options.clock
	local duration = options.duration or DEFAULT_DURATION
	local burst = options.burst or DEFAULT_BURST
	local flights: { Flight } = {}

	local function burstAt(target: BasePart, color: Color3)
		local attachment = target:FindFirstChild("FactoryCollectBurst")
		if attachment == nil then
			local created = Instance.new("Attachment")
			created.Name = "FactoryCollectBurst"
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "Burst"
			emitter.Enabled = false
			emitter.Lifetime = NumberRange.new(0.3, 0.6)
			emitter.Speed = NumberRange.new(6, 10)
			emitter.SpreadAngle = Vector2.new(180, 180)
			emitter.Size = NumberSequence.new(0.6, 0)
			emitter.LightEmission = 0.6
			emitter.Parent = created
			created.Parent = target
			attachment = created
		end
		local emitter = (attachment :: Instance):FindFirstChild("Burst")
		if emitter ~= nil and emitter:IsA("ParticleEmitter") then
			emitter.Color = ColorSequence.new(color)
			emitter:Emit(burst)
		end
	end

	local function finish(flight: Flight, arrived: boolean)
		if arrived and flight.target.Parent ~= nil then
			burstAt(flight.target, flight.color)
		end
		flight.part:Destroy()
	end

	local fx: CollectFx = {
		pull = function(_self, part: BasePart, target: BasePart?, color: Color3?): boolean
			if target == nil then
				return false
			end
			part.Parent = holder
			local tint = color or part.Color
			local fromAttachment = Instance.new("Attachment")
			fromAttachment.Parent = part
			local toAttachment = target:FindFirstChild("FactoryCollectTarget")
			if toAttachment == nil then
				local created = Instance.new("Attachment")
				created.Name = "FactoryCollectTarget"
				created.Parent = target
				toAttachment = created
			end
			local beam = Instance.new("Beam")
			beam.Attachment0 = fromAttachment
			beam.Attachment1 = toAttachment :: Attachment
			beam.FaceCamera = true
			beam.Width0 = 0.5
			beam.Width1 = 0.1
			beam.LightEmission = 0.8
			beam.Color = ColorSequence.new(tint)
			beam.Transparency = NumberSequence.new(0.2, 0.8)
			beam.Parent = part
			table.insert(flights, {
				part = part,
				target = target,
				from = part.Position,
				startSize = part.Size,
				startedAt = clock(),
				color = tint,
			})
			return true
		end,

		-- Bewegt alle Fluege; liefert die Zahl der noch laufenden.
		update = function(_self, now: number): number
			for index = #flights, 1, -1 do
				local flight = flights[index]
				local alpha = (now - flight.startedAt) / duration
				if flight.target.Parent == nil or flight.part.Parent == nil then
					table.remove(flights, index)
					finish(flight, false)
				elseif alpha >= 1 then
					table.remove(flights, index)
					finish(flight, true)
				else
					flight.part.Position = CollectFx.lerpPosition(flight.from, flight.target.Position, alpha)
					flight.part.Size = flight.startSize * (1 - 0.7 * math.clamp(alpha, 0, 1))
				end
			end
			return #flights
		end,

		active = function(_self): number
			return #flights
		end,

		destroy = function(_self)
			for _, flight in flights do
				flight.part:Destroy()
			end
			table.clear(flights)
		end,
	}
	return fx
end

return CollectFx
