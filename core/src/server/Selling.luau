--!strict
-- Verkauf: verwandelt das gesamte Inventar in Coins. Preise kommen aus der Config, der Multiplikator
-- ausschliesslich ueber Modifiers (factorStat). canSell ist der Erweiterungspunkt Sell-Ausloeser (spaeter Zone,
-- NPC oder Button); der Core ruft ihn nur auf, die Berechnung bleibt hier.
--
-- Ablauf: alles pruefen und berechnen, dann inventory:clear, dann economy:credit(ctx, earned, "sell").
-- earned = floor(Summe(Preis * Anzahl) * Faktor). Ist earned 0 (z. B. Faktor 0), wird das Inventar trotzdem
-- geleert, ohne Gutschrift und ohne Fehler.
--
-- Fehlercodes (err): NOT_AT_SELL_POINT, NOT_LOADED, CORRUPT_VALUE, NOTHING_TO_SELL, UNKNOWN_ITEM (Itemtyp wird
-- per warn genannt); bei jedem Fehler wird nichts geleert und nichts gutgeschrieben.
local Economy = require(script.Parent.Economy)
local Inventory = require(script.Parent.Inventory)
local Modifiers = require(script.Parent.Modifiers)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)

type PlayerContext = PlayerContext.PlayerContext

export type SellResult = {
	earned: number,
	sold: { [string]: number },
	err: string?,
}

export type Options = {
	inventory: Inventory.Inventory,
	economy: Economy.Economy,
	modifiers: Modifiers.Modifiers,
	prices: { [string]: number },
	factorStat: string?,
	canSell: (ctx: PlayerContext) -> boolean,
	onSold: ((ctx: PlayerContext, sale: { earned: number, sold: { [string]: number } }) -> ())?,
}

export type Selling = {
	sell: (self: Selling, ctx: PlayerContext) -> SellResult,
}

local DEFAULT_FACTOR_STAT = "sellFactor"

local Selling = {}

function Selling.new(options: Options): Selling
	assert(options.inventory ~= nil, "Selling: inventory must be set")
	assert(options.economy ~= nil, "Selling: economy must be set")
	assert(options.modifiers ~= nil, "Selling: modifiers must be set")
	assert(type(options.canSell) == "function", "Selling: canSell must be a function")
	assert(type(options.prices) == "table", "Selling: prices must be a table")
	for itemTypeId, price in options.prices do
		assert(
			type(price) == "number" and price > 0 and price < math.huge and price == math.floor(price),
			"Selling: price of " .. tostring(itemTypeId) .. " must be a whole number > 0"
		)
	end
	local factorStat = options.factorStat or DEFAULT_FACTOR_STAT
	assert(options.modifiers:has(factorStat), "Selling: modifiers has no base value for " .. factorStat)

	local inventory = options.inventory
	local economy = options.economy
	local modifiers = options.modifiers
	local prices = options.prices
	local canSell = options.canSell
	local onSold = options.onSold

	local function failed(err: string): SellResult
		return { earned = 0, sold = {}, err = err }
	end

	local selling: Selling = {
		sell = function(_self, ctx: PlayerContext): SellResult
			if not canSell(ctx) then
				return failed("NOT_AT_SELL_POINT")
			end
			local status = inventory:status(ctx)
			if status ~= "OK" then
				return failed(status)
			end
			-- Inventar ist geladen; ist der Kontostand trotzdem nicht lesbar, ist er beschaedigt.
			if economy:balance(ctx) == nil then
				return failed("CORRUPT_VALUE")
			end
			local contents = inventory:contents(ctx) :: Inventory.Contents
			if next(contents) == nil then
				return failed("NOTHING_TO_SELL")
			end

			local unknown: { string } = {}
			local sum = 0
			for itemTypeId, n in contents do
				local price = prices[itemTypeId]
				if price == nil then
					table.insert(unknown, itemTypeId)
				else
					sum += price * n
				end
			end
			if #unknown > 0 then
				table.sort(unknown)
				warn("[Selling] no price for item type(s): " .. table.concat(unknown, ", "))
				return failed("UNKNOWN_ITEM")
			end
			local earned = math.floor(sum * modifiers:value(ctx, factorStat))

			local sold = inventory:clear(ctx) :: Inventory.Contents
			if earned > 0 then
				local credited, creditErr = economy:credit(ctx, earned, "sell")
				if not credited then
					-- Nach den Vorpruefungen nicht erwartet; laut melden statt still verlieren.
					warn("[Selling] credit failed after clearing: " .. tostring(creditErr))
					return { earned = 0, sold = sold, err = creditErr }
				end
			end

			if onSold then
				local ok, callbackErr = pcall(onSold, ctx, { earned = earned, sold = table.clone(sold) })
				if not ok then
					warn("[Selling] onSold failed: " .. tostring(callbackErr))
				end
			end
			return { earned = earned, sold = sold, err = nil }
		end,
	}
	return selling
end

return Selling
