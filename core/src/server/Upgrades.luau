--!strict
-- Kaufbare Stufen pro Dimension. Kosten kommen aus der Config (ganze Zahlen > 0, streng steigend), die Wirkung
-- laeuft ausschliesslich ueber Modifiers (modifierSource). Wirkung einer Dimension = Eintrag der aktuellen
-- Stufe (nicht kumulativ); Stufe 0 = keine Wirkung.
--
-- Gespeichert: profile[field] = { [dimension]: Stufe }. Fehlendes Feld bzw. fehlende Dimension = 0.
-- Ein vorhandener ungueltiger Wert (Feld keine Tabelle, Stufe keine ganze Zahl, negativ oder groesser als die
-- Stufenzahl) wird nicht repariert: CORRUPT_VALUE, und die Quelle liefert keine Wirkung.
-- purchase bucht zuerst ueber Economy ab und erhoeht erst bei Erfolg die Stufe.
--
-- Fehlercodes: UNKNOWN_DIMENSION, NOT_LOADED, CORRUPT_VALUE, MAX_LEVEL, INSUFFICIENT_FUNDS (und weitere
-- Fehler aus economy:debit).
local Economy = require(script.Parent.Economy)
local Modifiers = require(script.Parent.Modifiers)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)

type PlayerContext = PlayerContext.PlayerContext
type Profile = { [string]: any }

export type Level = {
	cost: number,
	add: number?,
	mul: number?,
}

export type Dimension = {
	stat: string,
	levels: { Level },
}

export type Purchase = {
	dimension: string,
	level: number,
	cost: number,
}

export type Options = {
	getProfile: (ctx: PlayerContext) -> Profile?,
	economy: Economy.Economy,
	field: string?,
	dimensions: { [string]: Dimension },
	onUpgraded: ((ctx: PlayerContext, purchase: Purchase) -> ())?,
}

export type Upgrades = {
	level: (self: Upgrades, ctx: PlayerContext, dimension: string) -> number?,
	nextCost: (self: Upgrades, ctx: PlayerContext, dimension: string) -> number?,
	purchase: (self: Upgrades, ctx: PlayerContext, dimension: string) -> (boolean, string?),
	modifierSource: (self: Upgrades) -> Modifiers.Source,
}

local DEFAULT_FIELD = "upgrades"
local ID_PATTERN = "^[a-z][a-z0-9_]*$"

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isWhole(value: any): boolean
	return isFinite(value) and value == math.floor(value)
end

local Upgrades = {}

function Upgrades.new(options: Options): Upgrades
	assert(type(options.getProfile) == "function", "Upgrades: getProfile must be a function")
	assert(options.economy ~= nil, "Upgrades: economy must be set")
	local field = options.field or DEFAULT_FIELD
	assert(type(field) == "string" and field ~= "", "Upgrades: field must be a non-empty string")
	assert(type(options.dimensions) == "table", "Upgrades: dimensions must be a table")
	for dimension, config in options.dimensions do
		assert(
			type(dimension) == "string" and string.match(dimension, ID_PATTERN) ~= nil,
			"Upgrades: invalid dimension id " .. tostring(dimension)
		)
		assert(type(config.stat) == "string" and config.stat ~= "", "Upgrades: " .. dimension .. " needs a stat")
		assert(type(config.levels) == "table" and #config.levels >= 1, "Upgrades: " .. dimension .. " needs levels")
		local previousCost = 0
		for index, level in config.levels do
			local where = string.format("Upgrades: %s level %d", dimension, index)
			assert(isWhole(level.cost) and level.cost > previousCost, where .. ": cost must be whole, > 0 and rising")
			assert(level.add ~= nil or level.mul ~= nil, where .. ": needs add or mul")
			assert(level.add == nil or isFinite(level.add), where .. ": add must be finite")
			assert(level.mul == nil or (isFinite(level.mul) and level.mul >= 0), where .. ": mul must be finite >= 0")
			previousCost = level.cost
		end
	end

	local getProfile = options.getProfile
	local economy = options.economy
	local dimensions = options.dimensions
	local onUpgraded = options.onUpgraded

	-- Liefert die Stufentabelle; ein fehlendes Feld wird angelegt. nil = vorhandener Wert ungueltig.
	local function levels(profile: Profile): { [string]: number }?
		local stored = profile[field]
		if stored == nil then
			stored = {}
			profile[field] = stored
			return stored
		end
		if type(stored) ~= "table" then
			return nil
		end
		for dimension, config in dimensions do
			local value = stored[dimension]
			if value ~= nil and not (isWhole(value) and value >= 0 and value <= #config.levels) then
				return nil
			end
		end
		return stored
	end

	-- Liefert (Stufentabelle, nil) oder (nil, Fehlercode).
	local function loadLevels(ctx: PlayerContext): ({ [string]: number }?, string?)
		local profile = getProfile(ctx)
		if profile == nil then
			return nil, "NOT_LOADED"
		end
		local stored = levels(profile)
		if stored == nil then
			return nil, "CORRUPT_VALUE"
		end
		return stored, nil
	end

	local upgrades: Upgrades = {
		level = function(_self, ctx: PlayerContext, dimension: string): number?
			if dimensions[dimension] == nil then
				return nil
			end
			local stored = loadLevels(ctx)
			return if stored ~= nil then stored[dimension] or 0 else nil
		end,

		nextCost = function(_self, ctx: PlayerContext, dimension: string): number?
			local config = dimensions[dimension]
			if config == nil then
				return nil
			end
			local stored = loadLevels(ctx)
			if stored == nil then
				return nil
			end
			local nextLevel = config.levels[(stored[dimension] or 0) + 1]
			return if nextLevel ~= nil then nextLevel.cost else nil
		end,

		purchase = function(_self, ctx: PlayerContext, dimension: string): (boolean, string?)
			local config = dimensions[dimension]
			if config == nil then
				return false, "UNKNOWN_DIMENSION"
			end
			local stored, err = loadLevels(ctx)
			if stored == nil then
				return false, err
			end
			local current = stored[dimension] or 0
			local nextLevel = config.levels[current + 1]
			if nextLevel == nil then
				return false, "MAX_LEVEL"
			end
			local paid, debitErr = economy:debit(ctx, nextLevel.cost, "upgrade")
			if not paid then
				return false, debitErr
			end
			stored[dimension] = current + 1
			if onUpgraded then
				local ok, callbackErr =
					pcall(onUpgraded, ctx, { dimension = dimension, level = current + 1, cost = nextLevel.cost })
				if not ok then
					warn("[Upgrades] onUpgraded failed: " .. tostring(callbackErr))
				end
			end
			return true, nil
		end,

		modifierSource = function(_self): Modifiers.Source
			return function(ctx: PlayerContext): { [string]: Modifiers.Effect }
				local effects: { [string]: Modifiers.Effect } = {}
				local stored = loadLevels(ctx)
				if stored == nil then
					return effects
				end
				for dimension, config in dimensions do
					local current = stored[dimension] or 0
					local entry = config.levels[current]
					if current > 0 and entry ~= nil then
						local effect = effects[config.stat] or {}
						if entry.add ~= nil then
							effect.add = (effect.add or 0) + entry.add
						end
						if entry.mul ~= nil then
							effect.mul = (effect.mul or 1) * entry.mul
						end
						effects[config.stat] = effect
					end
				end
				return effects
			end
		end,
	}
	return upgrades
end

return Upgrades
