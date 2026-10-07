--!strict
-- Collect-Typ "Radius": liefert die Kandidaten nach Abstand aufsteigend sortiert (bei Gleichstand nach
-- instanceId), damit bei Platzmangel das Naechste zuerst aufgenommen wird.
--
-- Die massgebliche Reichweite kommt aus getRange (Collecting filtert die Kandidaten bereits mit
-- getRange + rangeTolerance, spaeter inkl. Upgrades). params.radius ist nur eine optionale zusaetzliche
-- Obergrenze; fehlt er, werden alle uebergebenen Kandidaten geliefert. Ein gesetzter ungueltiger Wert
-- (keine endliche Zahl >= 0) wirft einen Fehler.
local CollectType = require(script.Parent.CollectType)
local PlayerContext = require(script.Parent.Parent.Parent.shared.PlayerContext)

export type Params = {
	radius: number?,
}

type Hit = {
	instanceId: string,
	distance: number,
}

local Radius = {}

function Radius.select(
	_ctx: PlayerContext.PlayerContext,
	origin: Vector3,
	candidates: { CollectType.ItemInstance },
	params: Params?
): { string }
	local radius = if params ~= nil then params.radius else nil
	if radius ~= nil then
		assert(
			type(radius) == "number" and radius >= 0 and radius < math.huge,
			"Radius: params.radius must be a finite number >= 0"
		)
	end

	local hits: { Hit } = {}
	for _, candidate in candidates do
		local distance = (candidate.position - origin).Magnitude
		if radius == nil or distance <= radius then
			table.insert(hits, { instanceId = candidate.instanceId, distance = distance })
		end
	end
	table.sort(hits, function(a: Hit, b: Hit): boolean
		if a.distance ~= b.distance then
			return a.distance < b.distance
		end
		return a.instanceId < b.instanceId
	end)

	local ids = table.create(#hits)
	for i, hit in hits do
		ids[i] = hit.instanceId
	end
	return ids
end

return Radius
