--!strict
-- Die einzige Stelle, an der sich Boni verrechnen. Bonusquellen (Upgrades, spaeter z. B. Game-Pass-Effekte)
-- registrieren sich hier (Erweiterungspunkt Modifier-Quelle).
--
-- value(ctx, stat) = (base + Summe aller add) * Produkt aller mul, nie negativ und nie NaN.
-- Quellen laufen in pcall und in fester Reihenfolge (nach Name sortiert). Eine werfende Quelle oder ein
-- ungueltiger Eintrag (add/mul nicht endlich, mul < 0) wird fuer diesen Stat ignoriert und gedrosselt per Log
-- gemeldet (key = Quellenname + Stat). Unbekannte Stats und doppelte Quellennamen sind Programmierfehler (assert).
local Log = require(script.Parent.Parent.shared.Log)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)

type PlayerContext = PlayerContext.PlayerContext

export type Effect = {
	add: number?,
	mul: number?,
}

export type Source = (ctx: PlayerContext) -> { [string]: Effect }

export type Options = {
	base: { [string]: number },
	log: Log.Log?,
}

export type Modifiers = {
	registerSource: (self: Modifiers, name: string, source: Source) -> (),
	has: (self: Modifiers, stat: string) -> boolean,
	value: (self: Modifiers, ctx: PlayerContext, stat: string) -> number,
}

type Registered = {
	name: string,
	source: Source,
}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local Modifiers = {}

function Modifiers.new(options: Options): Modifiers
	local base: { [string]: number } = {}
	assert(type(options.base) == "table", "Modifiers: base must be a table")
	for stat, value in options.base do
		assert(type(stat) == "string" and stat ~= "", "Modifiers: stat names must be non-empty strings")
		assert(isFinite(value) and value >= 0, "Modifiers: base value of " .. stat .. " must be a finite number >= 0")
		base[stat] = value
	end

	local sources: { Registered } = {}
	local log = options.log or Log.new()

	local modifiers: Modifiers = {
		registerSource = function(_self, name: string, source: Source)
			assert(type(name) == "string" and name ~= "", "Modifiers: source name must be a non-empty string")
			assert(type(source) == "function", "Modifiers: source must be a function")
			for _, registered in sources do
				assert(registered.name ~= name, "Modifiers: source " .. name .. " is already registered")
			end
			table.insert(sources, { name = name, source = source })
			table.sort(sources, function(a: Registered, b: Registered): boolean
				return a.name < b.name
			end)
		end,

		has = function(_self, stat: string): boolean
			return base[stat] ~= nil
		end,

		value = function(_self, ctx: PlayerContext, stat: string): number
			local baseValue = base[stat]
			assert(baseValue ~= nil, "Modifiers: unknown stat " .. tostring(stat))
			local add, mul = 0, 1
			for _, registered in sources do
				local ok, effects = pcall(registered.source, ctx)
				local key = registered.name .. ":" .. stat
				if not ok then
					log:warnThrottled(key, "[Modifiers] source " .. registered.name .. " failed: " .. tostring(effects))
				elseif type(effects) ~= "table" then
					log:warnThrottled(key, "[Modifiers] source " .. registered.name .. " returned no table")
				else
					local effect = effects[stat]
					if effect ~= nil then
						local valid = type(effect) == "table"
							and (effect.add == nil or isFinite(effect.add))
							and (effect.mul == nil or (isFinite(effect.mul) and effect.mul >= 0))
						if valid then
							add += effect.add or 0
							mul *= effect.mul or 1
						else
							log:warnThrottled(
								key,
								"[Modifiers] source " .. registered.name .. " returned an invalid effect for " .. stat
							)
						end
					end
				end
			end
			local result = (baseValue + add) * mul
			if result ~= result or result < 0 then
				return 0
			end
			return result
		end,
	}
	return modifiers
end

return Modifiers
