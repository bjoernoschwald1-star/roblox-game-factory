--!strict
-- Reine Logik des Feedbacks: vergleicht zwei aufeinanderfolgende Schnappschuesse und liefert Ereignisse
-- { collected = n, earned = coins, upgraded = dimension, unlocked = zoneId, full = true, prestiged = Stufe,
-- prestigeMultiplier = neuer Faktor, albumNew = neuer Album-Eintrag (bei mehreren der alphabetisch erste),
-- albumNewCount, albumCompleted = neu belohnte Album-Gruppe }. Nach einem Prestige meldet compare nur prestiged (der Rueckbau von Coins,
-- Upgrades und Zonen ist kein eigenes Ereignis). Nur vorhandene
-- Ereignisse stehen in der Tabelle; gleiche Schnappschuesse ergeben eine leere Tabelle. Welche Darstellung zu
-- welchem Ereignis gehoert, legt die Effekt-Tabelle des Games fest (Erweiterungspunkt Feedback-Profil).
-- Seltenheit (optional rarities = { [itemTypeId] = "common" | "rare" | "epic" | "legendary" }): found ist der neu
-- ins Inventar gekommene Itemtyp mit der hoechsten Seltenheit ueber common, foundRarity dessen Stufe.
-- wowLevel(rarity): 0 = keine Einblendung, 1 = epic, 2 = legendary (staerker). Alles kommt aus dem Vergleich
-- zweier Schnappschuesse, es gibt keine eigene Remote.

export type Events = {
	collected: number?,
	earned: number?,
	upgraded: string?,
	unlocked: string?,
	full: boolean?,
	found: string?,
	foundRarity: string?,
	prestiged: number?,
	prestigeMultiplier: number?,
	albumNew: string?,
	albumNewCount: number?,
	albumCompleted: string?,
}

local RARITY_RANK: { [string]: number } = { common = 1, rare = 2, epic = 3, legendary = 4 }

local FeedbackModel = {}

FeedbackModel.RARITY_RANK = RARITY_RANK

function FeedbackModel.rank(rarity: string?): number
	return RARITY_RANK[rarity or "common"] or 1
end

function FeedbackModel.wowLevel(rarity: string?): number
	return math.max(FeedbackModel.rank(rarity) - 2, 0)
end

function FeedbackModel.isWow(rarity: string?): boolean
	return FeedbackModel.wowLevel(rarity) > 0
end

local function firstSorted(map: { [string]: boolean }): string?
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys[1]
end

-- Hoechste Seltenheit unter den neu hinzugekommenen Itemtypen (bei Gleichstand der alphabetisch erste).
local function bestFound(old: any, new: any, rarities: { [string]: string }): string?
	if type(new.inventory) ~= "table" then
		return nil
	end
	local before = if type(old.inventory) == "table" then old.inventory else {}
	local gained = {}
	for itemTypeId, count in new.inventory do
		if count > (before[itemTypeId] or 0) then
			table.insert(gained, itemTypeId)
		end
	end
	table.sort(gained)
	local bestId: string? = nil
	local bestRank = 1
	for _, itemTypeId in gained do
		local itemRank = FeedbackModel.rank(rarities[itemTypeId])
		if itemRank > bestRank then
			bestId, bestRank = itemTypeId, itemRank
		end
	end
	return bestId
end

function FeedbackModel.compare(old: any, new: any, rarities: { [string]: string }?): Events
	local events: Events = {}
	if old == nil or new == nil then
		return events
	end
	local oldPrestige, newPrestige = old.prestige, new.prestige
	if type(oldPrestige) == "table" and type(newPrestige) == "table" and newPrestige.level > oldPrestige.level then
		events.prestiged = newPrestige.level
		events.prestigeMultiplier = newPrestige.multiplier
		return events
	end
	if new.inventoryCount > old.inventoryCount then
		events.collected = new.inventoryCount - old.inventoryCount
	end
	if new.coins > old.coins then
		events.earned = new.coins - old.coins
	end
	local upgraded: { [string]: boolean } = {}
	for dimension, state in new.upgrades do
		local before = old.upgrades[dimension]
		if before ~= nil and state.level > before.level then
			upgraded[dimension] = true
		end
	end
	events.upgraded = firstSorted(upgraded)
	local unlocked: { [string]: boolean } = {}
	for zoneId, zone in new.zones do
		local before = old.zones[zoneId]
		if zone.unlocked and before ~= nil and not before.unlocked then
			unlocked[zoneId] = true
		end
	end
	events.unlocked = firstSorted(unlocked)
	local wasFull = old.inventoryCount >= old.capacity
	if not wasFull and new.inventoryCount >= new.capacity then
		events.full = true
	end
	local oldAlbum, newAlbum = old.collection, new.collection
	if type(oldAlbum) == "table" and type(newAlbum) == "table" then
		local added: { [string]: boolean } = {}
		local count = 0
		for entryId in newAlbum.found do
			if oldAlbum.found[entryId] ~= true then
				added[entryId] = true
				count += 1
			end
		end
		if count > 0 then
			events.albumNew = firstSorted(added)
			events.albumNewCount = count
		end
		local completed: { [string]: boolean } = {}
		for groupId, group in newAlbum.groups do
			local before = oldAlbum.groups[groupId]
			if group.done and before ~= nil and not before.done then
				completed[groupId] = true
			end
		end
		events.albumCompleted = firstSorted(completed)
	end
	if rarities ~= nil then
		local found = bestFound(old, new, rarities)
		if found ~= nil then
			events.found = found
			events.foundRarity = rarities[found]
		end
	end
	return events
end

return FeedbackModel
