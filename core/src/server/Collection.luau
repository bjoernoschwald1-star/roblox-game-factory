--!strict
-- Sammelalbum: merkt sich pro Spieler, welche Album-Eintraege er schon einmal eingesammelt hat, und vergibt je
-- vollstaendiger Gruppe genau einmal eine Belohnung. Theme-neutral; Gruppen, Eintraege und Belohnungen kommen aus
-- der Game-Config (config.collection). Ein Eintrag kann mehrere Itemtypen umfassen (z. B. dieselbe Form in zwei
-- Zonen); jeder Itemtyp gehoert hoechstens zu einem Eintrag.
--
-- Gespeichert: profile[field] = { found = { [entryId]: true }, rewarded = { [groupId]: true } }. Fehlendes Feld
-- = leeres Album und wird angelegt (alte Spielstaende bleiben gueltig, kein Migrationsschritt). Ein vorhandener
-- ungueltiger Wert (keine Tabelle, found/rewarded keine Tabelle, Werte nicht true, unbekannte Schluessel bleiben
-- erlaubt) wird nicht repariert: CORRUPT_VALUE, nichts wird vermerkt, keine Wirkung. Prestige setzt das Feld
-- nicht zurueck.
--
-- record(ctx, itemTypeIds) vermerkt neue Eintraege; jede vollstaendige, noch nicht belohnte Gruppe wird als
-- belohnt vermerkt und ihre Coins werden ueber economy:credit (Grund "collection") gutgeschrieben (scheitert die
-- Gutschrift, bleibt die Gruppe offen und der naechste Aufruf versucht es erneut).
-- Dauerhafte Boni wirken nur ueber Modifiers (modifierSource): je Stat Summe der add, Produkt der mul aller
-- belohnten Gruppen. onRecorded laeuft danach in pcall.
--
-- Fehlercodes: NOT_LOADED, CORRUPT_VALUE (und Fehler aus economy:credit, dann bleibt die Gruppe unbelohnt).
local Economy = require(script.Parent.Economy)
local Modifiers = require(script.Parent.Modifiers)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)

type PlayerContext = PlayerContext.PlayerContext
type Profile = { [string]: any }

export type Reward = {
	coins: number?,
	effects: { [string]: Modifiers.Effect }?,
}

export type Entry = {
	id: string,
	itemTypes: { string },
}

export type Group = {
	order: number,
	nameKey: string,
	entries: { Entry },
	reward: Reward,
}

export type RecordResult = {
	newEntries: { string },
	completedGroups: { string },
	err: string?,
}

export type GroupState = {
	order: number,
	entries: { string },
	found: number,
	done: boolean,
	rewardCoins: number,
	rewardEffects: { [string]: Modifiers.Effect },
}

export type State = {
	found: { [string]: boolean },
	foundCount: number,
	total: number,
	groups: { [string]: GroupState },
}

export type Options = {
	getProfile: (ctx: PlayerContext) -> Profile?,
	economy: Economy.Economy,
	groups: { [string]: Group },
	field: string?,
	onRecorded: ((ctx: PlayerContext, result: RecordResult) -> ())?,
}

export type Collection = {
	record: (self: Collection, ctx: PlayerContext, itemTypeIds: { string }) -> RecordResult,
	state: (self: Collection, ctx: PlayerContext) -> State?,
	entryOf: (self: Collection, itemTypeId: string) -> string?,
	modifierSource: (self: Collection) -> Modifiers.Source,
}

local DEFAULT_FIELD = "collection"

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

local Collection = {}

function Collection.new(options: Options): Collection
	assert(type(options.getProfile) == "function", "Collection: getProfile must be a function")
	assert(options.economy ~= nil, "Collection: economy must be set")
	assert(type(options.groups) == "table", "Collection: groups must be a table")
	local getProfile = options.getProfile
	local economy = options.economy
	local field = options.field or DEFAULT_FIELD
	local onRecorded = options.onRecorded

	-- Eintrag je Itemtyp und Gruppe je Eintrag; doppelte Zuordnungen sind Programmierfehler.
	local entryOfItem: { [string]: string } = {}
	local groupOfEntry: { [string]: string } = {}
	local total = 0
	local groupIds = sortedKeys(options.groups)
	for _, groupId in groupIds do
		local group = options.groups[groupId]
		assert(type(group.entries) == "table" and #group.entries >= 1, "Collection: " .. groupId .. " needs entries")
		for _, entry in group.entries do
			assert(groupOfEntry[entry.id] == nil, "Collection: entry " .. tostring(entry.id) .. " is used twice")
			groupOfEntry[entry.id] = groupId
			total += 1
			for _, itemTypeId in entry.itemTypes do
				assert(entryOfItem[itemTypeId] == nil, "Collection: item type " .. itemTypeId .. " is used twice")
				entryOfItem[itemTypeId] = entry.id
			end
		end
	end

	local function isSet(value: any): boolean
		if type(value) ~= "table" then
			return false
		end
		for key, flag in value do
			if type(key) ~= "string" or flag ~= true then
				return false
			end
		end
		return true
	end

	-- Album aus dem Profil; fehlendes Feld wird leer angelegt. nil = vorhandener Wert ungueltig.
	local function current(profile: Profile): { found: { [string]: boolean }, rewarded: { [string]: boolean } }?
		local value = profile[field]
		if value == nil then
			value = { found = {}, rewarded = {} }
			profile[field] = value
			return value
		end
		if type(value) ~= "table" or not isSet(value.found) or not isSet(value.rewarded) then
			return nil
		end
		return value
	end

	local function albumOf(ctx: PlayerContext): (any, string?)
		local profile = getProfile(ctx)
		if profile == nil then
			return nil, "NOT_LOADED"
		end
		local album = current(profile)
		if album == nil then
			return nil, "CORRUPT_VALUE"
		end
		return album, nil
	end

	local function complete(album: any, groupId: string): boolean
		for _, entry in options.groups[groupId].entries do
			if album.found[entry.id] ~= true then
				return false
			end
		end
		return true
	end

	local collection: Collection = {
		record = function(_self, ctx: PlayerContext, itemTypeIds: { string }): RecordResult
			local album, err = albumOf(ctx)
			if album == nil then
				return { newEntries = {}, completedGroups = {}, err = err }
			end
			local newEntries: { string } = {}
			for _, itemTypeId in itemTypeIds do
				local entryId = entryOfItem[itemTypeId]
				if entryId ~= nil and album.found[entryId] ~= true then
					album.found[entryId] = true
					table.insert(newEntries, entryId)
				end
			end
			table.sort(newEntries)
			local completedGroups: { string } = {}
			local creditErr: string? = nil
			-- Alle offenen Gruppen pruefen: eine gescheiterte Gutschrift wird beim naechsten Aufruf nachgeholt.
			for _, groupId in groupIds do
				if album.rewarded[groupId] ~= true and complete(album, groupId) then
					local coins = options.groups[groupId].reward.coins or 0
					local credited, problem = true, nil
					if coins > 0 then
						credited, problem = economy:credit(ctx, coins, "collection")
					end
					if credited then
						album.rewarded[groupId] = true
						table.insert(completedGroups, groupId)
					else
						-- Nicht erwartet (Album war lesbar); Gruppe bleibt offen, naechster Aufruf versucht es erneut.
						creditErr = problem
						warn("[Collection] reward credit failed: " .. tostring(problem))
					end
				end
			end
			local result = { newEntries = newEntries, completedGroups = completedGroups, err = creditErr }
			if onRecorded and (#newEntries > 0 or #completedGroups > 0) then
				local ok, callbackErr = pcall(onRecorded, ctx, table.clone(result))
				if not ok then
					warn("[Collection] onRecorded failed: " .. tostring(callbackErr))
				end
			end
			return result
		end,

		-- Nur lesend (legt hoechstens das fehlende Feld an); nil bei nicht geladenem oder beschaedigtem Album.
		state = function(_self, ctx: PlayerContext): State?
			local album = albumOf(ctx)
			if album == nil then
				return nil
			end
			local groups: { [string]: GroupState } = {}
			local foundCount = 0
			local found: { [string]: boolean } = {}
			for _, groupId in groupIds do
				local group = options.groups[groupId]
				local entries: { string } = {}
				local count = 0
				for _, entry in group.entries do
					table.insert(entries, entry.id)
					if album.found[entry.id] == true then
						count += 1
						found[entry.id] = true
					end
				end
				foundCount += count
				groups[groupId] = {
					order = group.order,
					entries = entries,
					found = count,
					done = album.rewarded[groupId] == true,
					rewardCoins = group.reward.coins or 0,
					rewardEffects = table.clone(group.reward.effects or {}),
				}
			end
			return { found = found, foundCount = foundCount, total = total, groups = groups }
		end,

		entryOf = function(_self, itemTypeId: string): string?
			return entryOfItem[itemTypeId]
		end,

		modifierSource = function(_self): Modifiers.Source
			return function(ctx: PlayerContext): { [string]: Modifiers.Effect }
				local album = albumOf(ctx)
				if album == nil then
					return {}
				end
				local combined: { [string]: Modifiers.Effect } = {}
				for _, groupId in groupIds do
					if album.rewarded[groupId] == true then
						for stat, effect in options.groups[groupId].reward.effects or {} do
							local sum = combined[stat] or { add = 0, mul = 1 }
							sum.add = (sum.add or 0) + (effect.add or 0)
							sum.mul = (sum.mul or 1) * (effect.mul or 1)
							combined[stat] = sum
						end
					end
				end
				return combined
			end
		end,
	}
	return collection
end

return Collection
