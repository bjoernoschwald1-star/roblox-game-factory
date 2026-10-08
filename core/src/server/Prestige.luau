--!strict
-- Prestige: Der Spieler setzt ab einer Coin-Schwelle seinen Fortschritt zurueck (Coins auf startCoins, Upgrades
-- und Zonen auf Anfang) und erhaelt dafuer dauerhaft einen hoeheren Verkaufsfaktor. Theme-neutral; Name und
-- Darstellung (z. B. "Schmelze") liefert das Game.
--
-- Gespeichert: profile[field] = Prestige-Stufe (ganze Zahl >= 0). Fehlendes Feld = 0 und wird angelegt (alte
-- Spielstaende bleiben gueltig, kein Migrationsschritt noetig). Ein vorhandener ungueltiger Wert wird nicht
-- repariert: CORRUPT_VALUE, keine Wirkung.
-- Wirkung nur ueber Modifiers (modifierSource): { sellFactor = { mul = 1 + Stufe * sellBonusPerLevel } }.
--
-- reset prueft alles zuerst (Profil, Coins, Upgrade- und Zonenfeld lesbar, Schwelle), aendert dann in einem Zug:
-- Stufe + 1, Coins = startCoins, upgrades = {}, zones = {}. Das Inventar bleibt. onReset laeuft danach in pcall.
-- Eine zweite Anfrage direkt danach scheitert an der Schwelle (Coins sind zurueckgesetzt).
--
-- Fehlercodes: NOT_LOADED, CORRUPT_VALUE, NOT_ENOUGH_COINS.
local Economy = require(script.Parent.Economy)
local Modifiers = require(script.Parent.Modifiers)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)

type PlayerContext = PlayerContext.PlayerContext
type Profile = { [string]: any }

export type Options = {
	getProfile: (ctx: PlayerContext) -> Profile?,
	economy: Economy.Economy,
	coinsRequired: number,
	sellBonusPerLevel: number,
	startCoins: number,
	field: string?,
	coinsField: string?,
	upgradesField: string?,
	zonesField: string?,
	factorStat: string?,
	onReset: ((ctx: PlayerContext, event: { level: number }) -> ())?,
}

export type Prestige = {
	level: (self: Prestige, ctx: PlayerContext) -> number?,
	multiplier: (self: Prestige, ctx: PlayerContext) -> number?,
	canReset: (self: Prestige, ctx: PlayerContext) -> (boolean, string?),
	reset: (self: Prestige, ctx: PlayerContext) -> (boolean, string?),
	modifierSource: (self: Prestige) -> Modifiers.Source,
	coinsRequired: number,
	sellBonusPerLevel: number,
}

local DEFAULT_FIELD = "prestige"

local function isWhole(value: any): boolean
	return type(value) == "number"
		and value == value
		and value >= 0
		and value < math.huge
		and value == math.floor(value)
end

local Prestige = {}

function Prestige.new(options: Options): Prestige
	assert(type(options.getProfile) == "function", "Prestige: getProfile must be a function")
	assert(options.economy ~= nil, "Prestige: economy must be set")
	assert(
		isWhole(options.coinsRequired) and options.coinsRequired > 0,
		"Prestige: coinsRequired must be a whole number > 0"
	)
	assert(
		type(options.sellBonusPerLevel) == "number"
			and options.sellBonusPerLevel > 0
			and options.sellBonusPerLevel < math.huge,
		"Prestige: sellBonusPerLevel must be a finite number > 0"
	)
	assert(isWhole(options.startCoins), "Prestige: startCoins must be a whole number >= 0")
	local getProfile = options.getProfile
	local economy = options.economy
	local field = options.field or DEFAULT_FIELD
	local upgradesField = options.upgradesField or "upgrades"
	local zonesField = options.zonesField or "zones"
	local coinsField = options.coinsField or "coins"
	local factorStat = options.factorStat or "sellFactor"
	local coinsRequired = options.coinsRequired
	local bonus = options.sellBonusPerLevel
	local startCoins = options.startCoins
	local onReset = options.onReset

	-- Stufe aus dem Profil; fehlendes Feld wird mit 0 angelegt. nil = vorhandener Wert ungueltig.
	local function current(profile: Profile): number?
		local value = profile[field]
		if value == nil then
			profile[field] = 0
			return 0
		end
		return if isWhole(value) then value else nil
	end

	local function levelOf(ctx: PlayerContext): (number?, string?)
		local profile = getProfile(ctx)
		if profile == nil then
			return nil, "NOT_LOADED"
		end
		local level = current(profile)
		if level == nil then
			return nil, "CORRUPT_VALUE"
		end
		return level, nil
	end

	-- Prueft alle Bedingungen ohne zu aendern; liefert das Profil und die aktuelle Stufe.
	local function check(ctx: PlayerContext): (Profile?, number?, string?)
		local profile = getProfile(ctx)
		if profile == nil then
			return nil, nil, "NOT_LOADED"
		end
		local level = current(profile)
		local balance = economy:balance(ctx)
		local upgrades = profile[upgradesField]
		local zones = profile[zonesField]
		if
			level == nil
			or balance == nil
			or (upgrades ~= nil and type(upgrades) ~= "table")
			or (zones ~= nil and type(zones) ~= "table")
		then
			return nil, nil, "CORRUPT_VALUE"
		end
		if balance < coinsRequired then
			return nil, nil, "NOT_ENOUGH_COINS"
		end
		return profile, level, nil
	end

	local prestige: Prestige = {
		coinsRequired = coinsRequired,
		sellBonusPerLevel = bonus,

		level = function(_self, ctx: PlayerContext): number?
			return (levelOf(ctx))
		end,

		multiplier = function(_self, ctx: PlayerContext): number?
			local level = levelOf(ctx)
			return if level ~= nil then 1 + level * bonus else nil
		end,

		canReset = function(_self, ctx: PlayerContext): (boolean, string?)
			local profile, _, err = check(ctx)
			return profile ~= nil, err
		end,

		reset = function(_self, ctx: PlayerContext): (boolean, string?)
			local profile, level, err = check(ctx)
			if profile == nil or level == nil then
				return false, err
			end
			local newLevel = level + 1
			profile[field] = newLevel
			profile[coinsField] = startCoins
			profile[upgradesField] = {}
			profile[zonesField] = {}
			if onReset then
				local ok, callbackErr = pcall(onReset, ctx, { level = newLevel })
				if not ok then
					warn("[Prestige] onReset failed: " .. tostring(callbackErr))
				end
			end
			return true, nil
		end,

		modifierSource = function(_self): Modifiers.Source
			return function(ctx: PlayerContext): { [string]: Modifiers.Effect }
				local level = levelOf(ctx)
				if level == nil or level == 0 then
					return {}
				end
				return { [factorStat] = { mul = 1 + level * bonus } }
			end
		end,
	}
	return prestige
end

return Prestige
