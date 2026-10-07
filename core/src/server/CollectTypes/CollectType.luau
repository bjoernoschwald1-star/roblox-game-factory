--!strict
-- Feste Schnittstelle fuer Collect-Typen (Erweiterungspunkt).
-- select(ctx, origin, candidates, params) liefert die instanceIds, die aufgenommen werden sollen, in
-- Prioritaetsreihenfolge. Der Core prueft das Ergebnis immer selbst (Kandidat, Zone, Reichweite, Inventar,
-- Rate-Limit); ein Collect-Typ kann also nichts aufnehmen lassen, was der Core nicht erlaubt.
local PlayerContext = require(script.Parent.Parent.Parent.shared.PlayerContext)

export type ItemInstance = {
	instanceId: string,
	itemTypeId: string,
	zoneId: string,
	position: Vector3,
}

export type CollectType = {
	select: (
		ctx: PlayerContext.PlayerContext,
		origin: Vector3,
		candidates: { ItemInstance },
		params: any
	) -> { string },
}

return {}
