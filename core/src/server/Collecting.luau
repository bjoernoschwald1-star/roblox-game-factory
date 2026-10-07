--!strict
-- Einsammeln: Spawner pro Spieler und Zone sowie serverseitig gepruefte Aufnahme ins Inventar.
-- Items werden pro Spieler instanziert. Abhaengigkeiten zu spaeteren Modulen (Zonenfreigabe, Reichweite,
-- Spawn-Positionen) kommen als injizierte Funktionen; Zeit und Zufall ebenfalls.
--
-- collect prueft immer im Core: Kandidat des Spielers, Zone frei, Reichweite (getRange + rangeTolerance),
-- freier Inventarplatz und Rate-Limit - unabhaengig davon, was der Collect-Typ zurueckgibt.
-- Fehlercodes (err): NOT_STARTED, NOT_LOADED (auch bei beschaedigtem Inventar), INVALID_ORIGIN,
-- COLLECT_TYPE_ERROR, FULL, RATE_LIMITED. onCollected laeuft in pcall; Fehler werden nur per warn gemeldet.
local CollectType = require(script.Parent.CollectTypes.CollectType)
local Inventory = require(script.Parent.Inventory)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)
local TableCopy = require(script.Parent.Parent.shared.TableCopy)

type PlayerContext = PlayerContext.PlayerContext
export type ItemInstance = CollectType.ItemInstance

export type ItemConfig = {
	zoneId: string,
	spawnWeight: number,
}

export type ZoneConfig = {
	density: number, -- maximale gleichzeitige Items pro Spieler in der Zone
	respawnSeconds: number,
}

export type RateLimit = {
	maxItems: number,
	windowSeconds: number,
}

export type Options = {
	items: { [string]: ItemConfig },
	zones: { [string]: ZoneConfig },
	inventory: Inventory.Inventory,
	isZoneUnlocked: (ctx: PlayerContext, zoneId: string) -> boolean,
	getRange: (ctx: PlayerContext) -> number,
	spawnPosition: (zoneId: string, rng: Random) -> Vector3,
	collectType: CollectType.CollectType,
	collectParams: any,
	rangeTolerance: number?,
	rateLimit: RateLimit,
	clock: (() -> number)?,
	rng: Random?,
	onCollected: ((ctx: PlayerContext, collected: { ItemInstance }) -> ())?,
}

export type CollectResult = {
	collected: { ItemInstance },
	rejected: number,
	err: string?,
}

export type Collecting = {
	startPlayer: (self: Collecting, ctx: PlayerContext) -> (boolean, string?),
	refill: (self: Collecting, ctx: PlayerContext) -> (boolean, string?),
	instances: (self: Collecting, ctx: PlayerContext) -> { ItemInstance }?,
	collect: (self: Collecting, ctx: PlayerContext, origin: Vector3) -> CollectResult,
	stopPlayer: (self: Collecting, ctx: PlayerContext) -> (),
}

type Entry = {
	seq: number,
	instance: ItemInstance,
}

type ZoneState = {
	active: number,
	respawnAt: { number }, -- Zeitpunkte, ab denen freigewordene Slots wieder gefuellt werden duerfen
}

type PlayerState = {
	nextSeq: number,
	entries: { [string]: Entry },
	zones: { [string]: ZoneState },
	collectTimes: { number },
}

type WeightedItem = {
	itemTypeId: string,
	weight: number,
}

local DEFAULT_RANGE_TOLERANCE = 2

local function isFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector(value: any): boolean
	return typeof(value) == "Vector3"
		and isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
end

local Collecting = {}

function Collecting.new(options: Options): Collecting
	local items, zones = options.items, options.zones
	assert(type(items) == "table" and type(zones) == "table", "Collecting: items and zones must be tables")
	for zoneId, zone in zones do
		assert(type(zoneId) == "string", "Collecting: zone ids must be strings")
		assert(
			type(zone.density) == "number" and zone.density >= 0 and zone.density == math.floor(zone.density),
			"Collecting: density must be a whole number >= 0 (zone " .. zoneId .. ")"
		)
		assert(
			isFiniteNumber(zone.respawnSeconds) and zone.respawnSeconds >= 0,
			"Collecting: respawnSeconds must be >= 0 (zone " .. zoneId .. ")"
		)
	end
	for itemTypeId, item in items do
		assert(type(itemTypeId) == "string" and itemTypeId ~= "", "Collecting: item ids must be non-empty strings")
		assert(zones[item.zoneId] ~= nil, "Collecting: item " .. itemTypeId .. " references an unknown zone")
		assert(
			isFiniteNumber(item.spawnWeight) and item.spawnWeight > 0,
			"Collecting: spawnWeight must be > 0 (item " .. itemTypeId .. ")"
		)
	end
	local rateLimit = options.rateLimit
	assert(type(rateLimit) == "table", "Collecting: rateLimit must be set")
	assert(isFiniteNumber(rateLimit.maxItems) and rateLimit.maxItems > 0, "Collecting: rateLimit.maxItems must be > 0")
	assert(
		isFiniteNumber(rateLimit.windowSeconds) and rateLimit.windowSeconds > 0,
		"Collecting: rateLimit.windowSeconds must be > 0"
	)
	local rangeTolerance = options.rangeTolerance or DEFAULT_RANGE_TOLERANCE
	assert(isFiniteNumber(rangeTolerance) and rangeTolerance >= 0, "Collecting: rangeTolerance must be >= 0")
	assert(type(options.collectType) == "table", "Collecting: collectType must be set")
	assert(type(options.collectType.select) == "function", "Collecting: collectType.select must be a function")
	for _, name in { "isZoneUnlocked", "getRange", "spawnPosition" } do
		assert(type((options :: any)[name]) == "function", "Collecting: " .. name .. " must be a function")
	end
	assert(options.inventory ~= nil, "Collecting: inventory must be set")

	local inventory = options.inventory
	local isZoneUnlocked = options.isZoneUnlocked
	local getRange = options.getRange
	local spawnPosition = options.spawnPosition
	local collectType = options.collectType
	local collectParams = options.collectParams
	local onCollected = options.onCollected
	local clock: () -> number = options.clock or function()
		return DateTime.now().UnixTimestampMillis / 1000
	end
	local rng: Random = options.rng or Random.new()

	-- Feste Reihenfolge fuer Zonen und Items, damit gleicher Seed gleiche Ergebnisse liefert.
	local zoneIds: { string } = {}
	for zoneId in zones do
		table.insert(zoneIds, zoneId)
	end
	table.sort(zoneIds)
	local weighted: { [string]: { WeightedItem } } = {}
	for _, zoneId in zoneIds do
		weighted[zoneId] = {}
	end
	for itemTypeId, item in items do
		table.insert(weighted[item.zoneId], { itemTypeId = itemTypeId, weight = item.spawnWeight })
	end
	for _, zoneId in zoneIds do
		assert(
			zones[zoneId].density == 0 or #weighted[zoneId] > 0,
			"Collecting: zone " .. zoneId .. " has density > 0 but no items"
		)
	end
	for _, list in weighted do
		table.sort(list, function(a: WeightedItem, b: WeightedItem): boolean
			return a.itemTypeId < b.itemTypeId
		end)
	end

	local players: { [number]: PlayerState } = {}

	local function pickItemType(zoneId: string): string?
		local list = weighted[zoneId]
		if #list == 0 then
			return nil
		end
		local sum = 0
		for _, entry in list do
			sum += entry.weight
		end
		local roll = rng:NextNumber() * sum
		for _, entry in list do
			roll -= entry.weight
			if roll < 0 then
				return entry.itemTypeId
			end
		end
		return list[#list].itemTypeId
	end

	local function spawnOne(state: PlayerState, zoneId: string): boolean
		local itemTypeId = pickItemType(zoneId)
		if itemTypeId == nil then
			return false
		end
		local position = spawnPosition(zoneId, rng)
		assert(isFiniteVector(position), "Collecting: spawnPosition must return a finite Vector3")
		local seq = state.nextSeq
		state.nextSeq += 1
		local instanceId = string.format("i%d", seq)
		state.entries[instanceId] = {
			seq = seq,
			instance = { instanceId = instanceId, itemTypeId = itemTypeId, zoneId = zoneId, position = position },
		}
		state.zones[zoneId].active += 1
		return true
	end

	-- Fuellt freigeschaltete Zonen bis density; freigewordene Slots erst nach Ablauf ihrer Respawn-Zeit.
	local function fill(ctx: PlayerContext, state: PlayerState)
		local now = clock()
		for _, zoneId in zoneIds do
			if isZoneUnlocked(ctx, zoneId) then
				local zoneState = state.zones[zoneId]
				local waiting: { number } = {}
				for _, at in zoneState.respawnAt do
					if now < at then
						table.insert(waiting, at)
					end
				end
				zoneState.respawnAt = waiting
				local free = zones[zoneId].density - zoneState.active - #waiting
				for _ = 1, free do
					if not spawnOne(state, zoneId) then
						break
					end
				end
			end
		end
	end

	local function sortedEntries(state: PlayerState): { Entry }
		local list: { Entry } = {}
		for _, entry in state.entries do
			table.insert(list, entry)
		end
		table.sort(list, function(a: Entry, b: Entry): boolean
			return a.seq < b.seq
		end)
		return list
	end

	local function reach(ctx: PlayerContext): number
		local range = getRange(ctx)
		if not isFiniteNumber(range) or range < 0 then
			range = 0
		end
		return range + rangeTolerance
	end

	local function result(collected: { ItemInstance }, rejected: number, err: string?): CollectResult
		return { collected = collected, rejected = rejected, err = err }
	end

	local collecting: Collecting

	collecting = {
		startPlayer = function(_self, ctx: PlayerContext): (boolean, string?)
			if players[ctx.userId] ~= nil then
				return false, "ALREADY_STARTED"
			end
			local state: PlayerState = { nextSeq = 1, entries = {}, zones = {}, collectTimes = {} }
			for _, zoneId in zoneIds do
				state.zones[zoneId] = { active = 0, respawnAt = {} }
			end
			players[ctx.userId] = state
			fill(ctx, state)
			return true, nil
		end,

		refill = function(_self, ctx: PlayerContext): (boolean, string?)
			local state = players[ctx.userId]
			if state == nil then
				return false, "NOT_STARTED"
			end
			fill(ctx, state)
			return true, nil
		end,

		instances = function(_self, ctx: PlayerContext): { ItemInstance }?
			local state = players[ctx.userId]
			if state == nil then
				return nil
			end
			local list = {}
			for _, entry in sortedEntries(state) do
				table.insert(list, TableCopy.copy(entry.instance))
			end
			return list
		end,

		collect = function(_self, ctx: PlayerContext, origin: Vector3): CollectResult
			local state = players[ctx.userId]
			if state == nil then
				return result({}, 0, "NOT_STARTED")
			end
			local free = inventory:freeSpace(ctx)
			if free == nil then
				return result({}, 0, "NOT_LOADED")
			end
			if not isFiniteVector(origin) then
				return result({}, 0, "INVALID_ORIGIN")
			end

			-- 2. Kandidaten: eigene Instanzen in freigeschalteten Zonen und in Reichweite.
			local maxDistance = reach(ctx)
			local unlocked: { [string]: boolean } = {}
			local function zoneOpen(zoneId: string): boolean
				if unlocked[zoneId] == nil then
					unlocked[zoneId] = isZoneUnlocked(ctx, zoneId) == true
				end
				return unlocked[zoneId]
			end
			local function eligible(instance: ItemInstance): boolean
				return zoneOpen(instance.zoneId) and (instance.position - origin).Magnitude <= maxDistance
			end
			local candidates: { ItemInstance } = {}
			local candidateIds: { [string]: boolean } = {}
			for _, entry in sortedEntries(state) do
				if eligible(entry.instance) then
					table.insert(candidates, TableCopy.copy(entry.instance))
					candidateIds[entry.instance.instanceId] = true
				end
			end

			-- 3. Collect-Typ befragen; er bekommt nur Kopien.
			local selectOk, selected = pcall(collectType.select, ctx, origin, candidates, collectParams)
			if not selectOk or type(selected) ~= "table" then
				return result({}, 0, "COLLECT_TYPE_ERROR")
			end

			-- 4. Rueckgabe erneut pruefen: bekannter Kandidat, hoechstens einmal, Zone frei, Reichweite.
			local valid: { Entry } = {}
			local seen: { [string]: boolean } = {}
			local rejected = 0
			for _, id in selected do
				local entry = if type(id) == "string" then state.entries[id] else nil
				if entry == nil or not candidateIds[id] or seen[id] or not eligible(entry.instance) then
					rejected += 1
				else
					seen[id] = true
					table.insert(valid, entry)
				end
			end

			-- 5. Begrenzen auf freien Platz und Rate-Limit (gleitendes Fenster).
			local now = clock()
			local recent: { number } = {}
			for _, at in state.collectTimes do
				if at > now - rateLimit.windowSeconds then
					table.insert(recent, at)
				end
			end
			state.collectTimes = recent
			local allowance = math.max(0, rateLimit.maxItems - #recent)
			local limit = math.min(free, allowance)
			local err: string? = nil
			if #valid > limit then
				err = if free <= allowance then "FULL" else "RATE_LIMITED"
				rejected += #valid - limit
				valid = table.move(valid, 1, limit, 1, {})
			end

			-- 6. Ins Inventar buchen (je Itemtyp), Instanzen entfernen, Respawn-Zeitpunkte merken.
			local byType: { [string]: { Entry } } = {}
			local typeOrder: { string } = {}
			for _, entry in valid do
				local itemTypeId = entry.instance.itemTypeId
				if byType[itemTypeId] == nil then
					byType[itemTypeId] = {}
					table.insert(typeOrder, itemTypeId)
				end
				table.insert(byType[itemTypeId], entry)
			end
			local booked: { [string]: boolean } = {}
			for _, itemTypeId in typeOrder do
				local addOk, addErr = inventory:add(ctx, itemTypeId, #byType[itemTypeId])
				if addOk then
					booked[itemTypeId] = true
				else
					rejected += #byType[itemTypeId]
					err = addErr
				end
			end
			local collected: { ItemInstance } = {}
			for _, entry in valid do
				local instance = entry.instance
				if booked[instance.itemTypeId] then
					state.entries[instance.instanceId] = nil
					local zoneState = state.zones[instance.zoneId]
					zoneState.active -= 1
					table.insert(zoneState.respawnAt, now + zones[instance.zoneId].respawnSeconds)
					table.insert(state.collectTimes, now)
					table.insert(collected, TableCopy.copy(instance))
				end
			end

			-- Callback-Fehler aendern weder Ergebnis noch gebuchten Zustand.
			if onCollected and #collected > 0 then
				local callbackOk, callbackErr = pcall(onCollected, ctx, TableCopy.copy(collected))
				if not callbackOk then
					warn("[Collecting] onCollected failed: " .. tostring(callbackErr))
				end
			end
			return result(collected, rejected, err)
		end,

		stopPlayer = function(_self, ctx: PlayerContext)
			players[ctx.userId] = nil
		end,
	}
	return collecting
end

return Collecting
