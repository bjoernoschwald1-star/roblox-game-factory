--!strict
-- Typisiertes Config-Schema eines Games. Die Config ist die einzige Quelle fuer Spielwerte; Code liest sie,
-- schreibt sie nie. Alle IDs entsprechen ID_PATTERN. Asset-Referenzen sind abstrakte Schluessel (z. B.
-- "item_small"); die Zuordnung zu echten Assets macht spaeter das Kit bzw. das Game.
-- Product- und Pass-IDs sind in Phase 0 Platzhalter (ganze Zahlen > 0); products und passes duerfen leer sein.

export type Effect = {
	add: number?,
	mul: number?,
}

export type GameSection = {
	id: string,
	configVersion: string,
	startCoins: number, -- ganze Zahl >= 0
	schemaVersion: number, -- ganze Zahl >= 1
	base: { range: number, capacity: number, sellFactor: number },
}

export type ItemConfig = {
	zoneId: string,
	spawnWeight: number,
	price: number, -- ganze Zahl > 0 (Verkaufspreis in Coins)
	asset: string, -- abstrakter Asset-Schluessel
	nameKey: string,
	rarity: string?, -- einer von RARITIES; fehlt -> DEFAULT_RARITY (nur Darstellung, keine Spiellogik)
}

export type Condition = { type: string, [string]: any }

export type ZoneConfig = {
	order: number,
	density: number,
	respawnSeconds: number,
	condition: Condition,
	nameKey: string,
}

export type UpgradeLevel = {
	cost: number,
	add: number?,
	mul: number?,
}

export type UpgradeConfig = {
	stat: string, -- einer von STATS
	levels: { UpgradeLevel },
	nameKey: string,
}

export type CollectConfig = {
	type: string, -- einer von COLLECT_TYPES
	params: { radius: number? },
	rangeTolerance: number,
	rateLimit: { maxItems: number, windowSeconds: number },
}

export type SellConfig = {
	trigger: string, -- einer von SELL_TRIGGERS
}

export type Reward = {
	type: string, -- "coins" oder "perk"
	amount: number?,
	perkId: string?,
}

export type ProductConfig = {
	productId: number,
	rewards: { Reward },
}

export type PassConfig = {
	passId: number,
	effects: { [string]: Effect },
}

export type RemoteLimit = {
	max: number,
	windowSeconds: number,
}

-- Prestige (optional): Zuruecksetzen gegen einen dauerhaften Verkaufsmultiplikator. Ab coinsRequired Coins darf
-- der Spieler zuruecksetzen; jede Prestige-Stufe erhoeht den Verkaufsfaktor um sellBonusPerLevel
-- (Faktor = 1 + Stufe * sellBonusPerLevel, wirkt als mul auf sellFactor).
export type PrestigeConfig = {
	coinsRequired: number, -- ganze Zahl > 0
	sellBonusPerLevel: number, -- > 0
}

-- Sammelalbum (optional): Gruppen mit Eintraegen (je Eintrag ein oder mehrere Itemtypen) und einer einmaligen
-- Belohnung je vollstaendiger Gruppe (coins und/oder dauerhafte effects auf Stats wie bei Paessen).
export type CollectionEntry = {
	id: string,
	itemTypes: { string },
}

export type CollectionGroup = {
	order: number, -- ganze Zahl >= 1, eindeutig
	nameKey: string,
	entries: { CollectionEntry },
	reward: { coins: number?, effects: { [string]: Effect }? },
}

export type CollectionConfig = {
	groups: { [string]: CollectionGroup },
}

export type SimConfig = {
	tripSeconds: number, -- Zusatzzeit je Sammelfahrt
	sellSeconds: number, -- Zusatzzeit je Verkauf
}

export type GameConfig = {
	game: GameSection,
	items: { [string]: ItemConfig },
	zones: { [string]: ZoneConfig },
	upgrades: { [string]: UpgradeConfig },
	collect: CollectConfig,
	sell: SellConfig,
	products: { [string]: ProductConfig },
	passes: { [string]: PassConfig },
	remotes: { [string]: RemoteLimit },
	texts: { [string]: string },
	sim: SimConfig,
	prestige: PrestigeConfig?,
	collection: CollectionConfig?,
}

local Schema = {}

Schema.ID_PATTERN = "^[a-z][a-z0-9_]*$"
Schema.STATS = table.freeze({ "range", "capacity", "sellFactor" })
Schema.COLLECT_TYPES = table.freeze({ "radius" })
Schema.SELL_TRIGGERS = table.freeze({ "zone", "npc", "button" })
Schema.REWARD_TYPES = table.freeze({ "coins", "perk" })
Schema.CONDITION_TYPES = table.freeze({ "always", "coinsAtLeast", "purchase", "upgradeLevel" })
Schema.REMOTES = table.freeze({ "collect", "sell", "buyUpgrade", "unlockZone", "prestige" })
-- Seltenheit eines Itemtyps; Wirkung im Spiel nur ueber eigenen spawnWeight und price, sonst reine Anzeige.
Schema.RARITIES = table.freeze({ "common", "rare", "epic", "legendary" })
Schema.DEFAULT_RARITY = "common"

return table.freeze(Schema)
