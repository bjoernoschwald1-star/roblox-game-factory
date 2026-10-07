--!strict
-- Kontostand eines Spielers im geladenen Profil. Server-autoritativ: Betraege und Gruende werden geprueft,
-- der Kontostand ist immer eine ganze Zahl zwischen 0 und maxBalance.
--
-- Wie im ProfileStore wird ein vorhandener Stand nie still ueberschrieben: Fehlt das Feld, gilt 0 und es
-- wird angelegt; ein vorhandener ungueltiger Wert wird nicht repariert (balance nil, CORRUPT_VALUE).
-- onTransaction laeuft in pcall; Fehler werden nur per warn gemeldet.
--
-- Fehlercodes: INVALID_AMOUNT, INVALID_REASON, NOT_LOADED, CORRUPT_VALUE, INSUFFICIENT_FUNDS.
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)

type PlayerContext = PlayerContext.PlayerContext
type Profile = { [string]: any }

export type Transaction = {
	delta: number,
	balance: number,
	reason: string,
}

export type Options = {
	getProfile: (ctx: PlayerContext) -> Profile?,
	field: string?,
	maxBalance: number?,
	onTransaction: ((ctx: PlayerContext, transaction: Transaction) -> ())?,
}

export type Economy = {
	balance: (self: Economy, ctx: PlayerContext) -> number?,
	credit: (self: Economy, ctx: PlayerContext, amount: number, reason: string) -> (boolean, string?),
	debit: (self: Economy, ctx: PlayerContext, amount: number, reason: string) -> (boolean, string?),
}

local DEFAULT_FIELD = "coins"
local DEFAULT_MAX_BALANCE = 1e12
local REASON_PATTERN = "^[a-z][a-z0-9_]*$"

local function isWholeAmount(value: any): boolean
	return type(value) == "number" and value > 0 and value < math.huge and value == math.floor(value)
end

local Economy = {}

function Economy.new(options: Options): Economy
	assert(type(options.getProfile) == "function", "Economy: getProfile must be a function")
	local field = options.field or DEFAULT_FIELD
	local maxBalance = options.maxBalance or DEFAULT_MAX_BALANCE
	assert(type(field) == "string" and field ~= "", "Economy: field must be a non-empty string")
	assert(isWholeAmount(maxBalance), "Economy: maxBalance must be a positive whole number")
	local getProfile = options.getProfile
	local onTransaction = options.onTransaction

	-- Liefert den Kontostand; ein fehlendes Feld wird mit 0 angelegt. nil = vorhandener Wert ungueltig.
	local function current(profile: Profile): number?
		local value = profile[field]
		if value == nil then
			profile[field] = 0
			return 0
		end
		if type(value) ~= "number" or not (value >= 0 and value <= maxBalance) or value ~= math.floor(value) then
			return nil
		end
		return value
	end

	local function validate(amount: any, reason: any): string?
		if not isWholeAmount(amount) then
			return "INVALID_AMOUNT"
		end
		if type(reason) ~= "string" or string.match(reason, REASON_PATTERN) == nil then
			return "INVALID_REASON"
		end
		return nil
	end

	-- Prueft Eingaben und Profil; liefert Profil und Kontostand oder einen Fehlercode.
	local function prepare(ctx: PlayerContext, amount: any, reason: any): (Profile?, number?, string?)
		local invalid = validate(amount, reason)
		if invalid then
			return nil, nil, invalid
		end
		local profile = getProfile(ctx)
		if profile == nil then
			return nil, nil, "NOT_LOADED"
		end
		local before = current(profile)
		if before == nil then
			return nil, nil, "CORRUPT_VALUE"
		end
		return profile, before, nil
	end

	local function apply(ctx: PlayerContext, profile: Profile, before: number, after: number, reason: string)
		if after == before then
			return
		end
		profile[field] = after
		if onTransaction then
			-- Callback-Fehler aendern weder Ergebnis noch gebuchten Stand.
			local ok, err = pcall(onTransaction, ctx, { delta = after - before, balance = after, reason = reason })
			if not ok then
				warn("[Economy] onTransaction failed: " .. tostring(err))
			end
		end
	end

	local economy: Economy = {
		balance = function(_self, ctx: PlayerContext): number?
			local profile = getProfile(ctx)
			return if profile ~= nil then current(profile) else nil
		end,

		credit = function(_self, ctx: PlayerContext, amount: number, reason: string): (boolean, string?)
			local profile, before, err = prepare(ctx, amount, reason)
			if profile == nil or before == nil then
				return false, err
			end
			apply(ctx, profile, before, math.min(before + amount, maxBalance), reason)
			return true, nil
		end,

		debit = function(_self, ctx: PlayerContext, amount: number, reason: string): (boolean, string?)
			local profile, before, err = prepare(ctx, amount, reason)
			if profile == nil or before == nil then
				return false, err
			end
			if amount > before then
				return false, "INSUFFICIENT_FUNDS"
			end
			apply(ctx, profile, before, before - amount, reason)
			return true, nil
		end,
	}
	return economy
end

return Economy
