--!strict
-- Reine Logik des Feedbacks: vergleicht zwei aufeinanderfolgende Schnappschuesse und liefert Ereignisse
-- { collected = n, earned = coins, upgraded = dimension, unlocked = zoneId, full = true }. Nur vorhandene
-- Ereignisse stehen in der Tabelle; gleiche Schnappschuesse ergeben eine leere Tabelle. Welche Darstellung zu
-- welchem Ereignis gehoert, legt die Effekt-Tabelle des Games fest (Erweiterungspunkt Feedback-Profil).

export type Events = {
	collected: number?,
	earned: number?,
	upgraded: string?,
	unlocked: string?,
	full: boolean?,
}

local FeedbackModel = {}

local function firstSorted(map: { [string]: boolean }): string?
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys[1]
end

function FeedbackModel.compare(old: any, new: any): Events
	local events: Events = {}
	if old == nil or new == nil then
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
	return events
end

return FeedbackModel
