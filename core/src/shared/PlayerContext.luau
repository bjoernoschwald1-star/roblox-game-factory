--!strict
-- Abstrakter Spieler-Kontext: Server-Module erhalten diesen statt eines Roblox-Player-Objekts.
-- Tests erzeugen ihn direkt, z. B. { userId = 101 }.

export type PlayerContext = {
	userId: number,
}

return {}
