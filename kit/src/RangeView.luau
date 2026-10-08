--!strict
-- Reichweiten-Kreis im Client: zeigt nach einer Aenderung der Reichweite (range aus dem Schnappschuss, z. B. nach
-- einem Upgrade) fuer SHOW_SECONDS einen leuchtenden Ring um die Figur, der in GROW_SECONDS vom alten auf den neuen
-- Radius waechst. Der Ring besteht aus SEGMENTS schmalen Parts (ohne Union), damit die Mitte frei bleibt.
-- Der erste Wert nach dem Start zeigt nichts (keine Aenderung). Rein clientseitig und nur Anzeige; die Uhr kommt
-- von aussen (Test: feste Zeiten). Keine Assets.

export type RangeView = {
	update: (self: RangeView, root: BasePart?, range: number?, now: number) -> boolean,
	ring: (self: RangeView) -> Model,
	destroy: (self: RangeView) -> (),
}

local SHOW_SECONDS = 3
local GROW_SECONDS = 0.6
local SEGMENTS = 40
local GROUND_OFFSET = 2.9 -- Wurzelteil steht etwa so hoch ueber dem Boden

local RangeView = {}

RangeView.SHOW_SECONDS = SHOW_SECONDS
RangeView.GROW_SECONDS = GROW_SECONDS
RangeView.SEGMENTS = SEGMENTS

-- Radius zum Zeitpunkt now (Ease-Out vom alten zum neuen Wert).
function RangeView.radiusAt(from: number, to: number, startedAt: number, now: number): number
	local alpha = math.clamp((now - startedAt) / GROW_SECONDS, 0, 1)
	local eased = 1 - (1 - alpha) * (1 - alpha)
	return from + (to - from) * eased
end

function RangeView.new(worldParent: Instance, color: Color3?): RangeView
	local ring = Instance.new("Model")
	ring.Name = "FactoryRangeRing"
	local segments: { Part } = {}
	for index = 1, SEGMENTS do
		local segment = Instance.new("Part")
		segment.Name = "Segment" .. index
		segment.Anchored = true
		segment.CanCollide = false
		segment.CanQuery = false
		segment.CanTouch = false
		segment.Material = Enum.Material.Neon
		segment.Color = color or Color3.fromRGB(255, 200, 40)
		segment.Transparency = 1
		segment.Size = Vector3.new(0.3, 0.12, 1)
		segment.Parent = ring
		segments[index] = segment
	end
	ring.Parent = worldParent

	local shown: number? = nil
	local from = 0
	local to = 0
	local startedAt = -math.huge

	local function setTransparency(value: number)
		for _, segment in segments do
			segment.Transparency = value
		end
	end

	local view: RangeView = {
		-- Liefert true, solange der Ring sichtbar ist.
		update = function(_self, root: BasePart?, range: number?, now: number): boolean
			if type(range) == "number" then
				if shown == nil then
					shown = range
				elseif range ~= shown then
					from = if now - startedAt < SHOW_SECONDS
						then RangeView.radiusAt(from, to, startedAt, now)
						else shown :: number
					to = range
					shown = range
					startedAt = now
				end
			end
			local visible = root ~= nil and now - startedAt < SHOW_SECONDS
			if not visible then
				setTransparency(1)
				return false
			end
			local radius = RangeView.radiusAt(from, to, startedAt, now)
			local center = (root :: BasePart).Position - Vector3.new(0, GROUND_OFFSET, 0)
			local length = 2 * math.pi * radius / SEGMENTS * 0.7
			for index, segment in segments do
				local angle = 2 * math.pi * index / SEGMENTS
				segment.Size = Vector3.new(0.3, 0.12, length)
				segment.CFrame = CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(radius, 0, 0)
			end
			-- Am Ende der Anzeige ausblenden.
			local fade = math.clamp((now - startedAt - (SHOW_SECONDS - 0.8)) / 0.8, 0, 1)
			setTransparency(0.2 + 0.8 * fade)
			return true
		end,
		ring = function(_self): Model
			return ring
		end,
		destroy = function(_self)
			ring:Destroy()
		end,
	}
	return view
end

return RangeView
