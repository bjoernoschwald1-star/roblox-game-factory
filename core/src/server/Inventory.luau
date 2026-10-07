--!strict
-- Inventar eines Spielers im geladenen Profil: { [itemTypeId]: Anzahl } mit Kapazitaetsgrenze.
-- Gespeichert werden nur positive ganze Anzahlen; leere Eintraege werden entfernt.
--
-- Wie im ProfileStore wird ein vorhandener Stand nie still ueberschrieben: Fehlt das Feld, gilt das Inventar
-- als leer und wird angelegt. Ist das Feld keine Tabelle oder enthaelt es einen ungueltigen Eintrag, liefern
-- count, freeSpace, contents und clear nil, add liefert CORRUPT_VALUE, und nichts wird veraendert.
-- status(ctx) unterscheidet "OK", "NOT_LOADED" und "CORRUPT_VALUE".
--
-- Fehlercodes: NOT_LOADED, INVALID_ITEM, INVALID_AMOUNT, CORRUPT_VALUE, FULL.
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)
local TableCopy = require(script.Parent.Parent.shared.TableCopy)

type PlayerContext = PlayerContext.PlayerContext
type Profile = { [string]: any }

export type Contents = { [string]: number }

export type Options = {
	getProfile: (ctx: PlayerContext) -> Profile?,
	field: string?,
	getCapacity: (ctx: PlayerContext) -> number,
}

export type Status = "OK" | "NOT_LOADED" | "CORRUPT_VALUE"

export type Inventory = {
	status: (self: Inventory, ctx: PlayerContext) -> Status,
	count: (self: Inventory, ctx: PlayerContext) -> number?,
	freeSpace: (self: Inventory, ctx: PlayerContext) -> number?,
	contents: (self: Inventory, ctx: PlayerContext) -> Contents?,
	add: (self: Inventory, ctx: PlayerContext, itemTypeId: string, n: number) -> (boolean, string?),
	clear: (self: Inventory, ctx: PlayerContext) -> Contents?,
}

local DEFAULT_FIELD = "inventory"

local function isWholeAmount(value: any): boolean
	return type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value)
end

local Inventory = {}

function Inventory.new(options: Options): Inventory
	assert(type(options.getProfile) == "function", "Inventory: getProfile must be a function")
	assert(type(options.getCapacity) == "function", "Inventory: getCapacity must be a function")
	local field = options.field or DEFAULT_FIELD
	assert(type(field) == "string" and field ~= "", "Inventory: field must be a non-empty string")
	local getProfile = options.getProfile
	local getCapacity = options.getCapacity

	-- Liefert die Inventartabelle des Profils; ein fehlendes Feld wird leer angelegt.
	-- nil = vorhandener Wert ungueltig (keine Tabelle oder ungueltiger Eintrag).
	local function bag(profile: Profile): Contents?
		local stored = profile[field]
		if stored == nil then
			stored = {}
			profile[field] = stored
			return stored
		end
		if type(stored) ~= "table" then
			return nil
		end
		for itemTypeId, n in stored do
			if type(itemTypeId) ~= "string" or itemTypeId == "" or not isWholeAmount(n) then
				return nil
			end
		end
		return stored
	end

	local function loadedBag(ctx: PlayerContext): Contents?
		local profile = getProfile(ctx)
		return if profile ~= nil then bag(profile) else nil
	end

	local function total(contents: Contents): number
		local sum = 0
		for _, n in contents do
			sum += n
		end
		return sum
	end

	-- Kapazitaet als ganze Zahl >= 0, auch wenn die (berechnete) Quelle Unsinn liefert.
	local function capacity(ctx: PlayerContext): number
		local value = getCapacity(ctx)
		if type(value) ~= "number" or value ~= value or value <= 0 then
			return 0
		end
		return math.floor(value)
	end

	local function freeIn(ctx: PlayerContext, contents: Contents): number
		return math.max(0, capacity(ctx) - total(contents))
	end

	local inventory: Inventory = {
		status = function(_self, ctx: PlayerContext): Status
			local profile = getProfile(ctx)
			if profile == nil then
				return "NOT_LOADED"
			end
			return if bag(profile) ~= nil then "OK" else "CORRUPT_VALUE"
		end,

		count = function(_self, ctx: PlayerContext): number?
			local contents = loadedBag(ctx)
			return if contents ~= nil then total(contents) else nil
		end,

		freeSpace = function(_self, ctx: PlayerContext): number?
			local contents = loadedBag(ctx)
			return if contents ~= nil then freeIn(ctx, contents) else nil
		end,

		contents = function(_self, ctx: PlayerContext): Contents?
			local contents = loadedBag(ctx)
			return if contents ~= nil then TableCopy.copy(contents) else nil
		end,

		add = function(_self, ctx: PlayerContext, itemTypeId: string, n: number): (boolean, string?)
			if type(itemTypeId) ~= "string" or itemTypeId == "" then
				return false, "INVALID_ITEM"
			end
			if not isWholeAmount(n) then
				return false, "INVALID_AMOUNT"
			end
			local profile = getProfile(ctx)
			if profile == nil then
				return false, "NOT_LOADED"
			end
			local contents = bag(profile)
			if contents == nil then
				return false, "CORRUPT_VALUE"
			end
			if n > freeIn(ctx, contents) then
				return false, "FULL"
			end
			contents[itemTypeId] = (contents[itemTypeId] or 0) + n
			return true, nil
		end,

		clear = function(_self, ctx: PlayerContext): Contents?
			local profile = getProfile(ctx)
			if profile == nil then
				return nil
			end
			local contents = bag(profile)
			if contents == nil then
				return nil
			end
			local removed = TableCopy.copy(contents)
			profile[field] = {}
			return removed
		end,
	}
	return inventory
end

return Inventory
