--!strict
-- Developer Products (idempotent ueber PurchaseId) und Game Passes (nur als Modifier-Quelle).
-- Roblox-Dienste kommen als injizierte Funktionen herein; dieses Modul ruft keine Engine-Dienste auf.
--
-- processReceipt vergibt Rewards ausschliesslich hier (nie bei "Prompt geschlossen") und meldet
-- "PurchaseGranted" erst, nachdem das Profil mit Reward und PurchaseId gespeichert wurde. Ist der Spieler nicht
-- geladen oder scheitert das Speichern, lautet die Antwort "NotProcessedYet"; Roblox liefert die Quittung
-- spaeter erneut. Deshalb wird ein nicht sicher gespeicherter Kauf im Speicher wieder zurueckgebaut (Coins per
-- Gegenbuchung, neu vergebene Perks entfernen, PurchaseId entfernen): Bliebe er stehen, wuerde ihn das naechste
-- Autosave still festschreiben, waehrend Roblox ihn noch als offen fuehrt. Andere Profilaenderungen, die
-- waehrend des Speicherns passieren, werden nicht angetastet. Doppelte Wirkung bei Serverwechsel verhindern
-- Session-Lock und die gespeicherte PurchaseId-Liste (neueste vorne, hoechstens maxRemembered Eintraege).
--
-- Reward-Typen: { type = "coins", amount } und { type = "perk", perkId }. Ein Buendel (z. B. VIP) ist nur
-- eine Liste von Rewards in der Config. Preise kennt der Core nicht.
-- Game Passes: Besitz wird ueber ownsPass abgefragt (refreshPasses, in pcall) und im Speicher gecacht;
-- modifierSource liest nur den Cache und veraendert nie gespeicherte Werte.
local Economy = require(script.Parent.Economy)
local Modifiers = require(script.Parent.Modifiers)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)
local PlayerSession = require(script.Parent.PlayerSession)

type PlayerContext = PlayerContext.PlayerContext
type Profile = { [string]: any }

export type Reward = {
	type: string, -- "coins" oder "perk"
	amount: number?,
	perkId: string?,
}

export type Product = {
	role: string,
	rewards: { Reward },
}

export type Pass = {
	passId: number,
	effects: { [string]: Modifiers.Effect },
}

export type Receipt = {
	PurchaseId: string,
	PlayerId: number,
	ProductId: number,
}

export type Decision = "PurchaseGranted" | "NotProcessedYet"

export type Options = {
	getProfile: (ctx: PlayerContext) -> Profile?,
	session: PlayerSession.PlayerSession,
	economy: Economy.Economy,
	products: { [number]: Product },
	passes: { [string]: Pass },
	ownsPass: (userId: number, passId: number) -> boolean,
	field: string?,
	perksField: string?,
	maxRemembered: number?,
	clock: (() -> number)?,
	onPurchase: ((ctx: PlayerContext, purchase: { role: string, purchaseId: string }) -> ())?,
}

export type Monetization = {
	processReceipt: (self: Monetization, receipt: Receipt) -> Decision,
	hasPerk: (self: Monetization, ctx: PlayerContext, perkId: string) -> boolean,
	refreshPasses: (self: Monetization, ctx: PlayerContext) -> (),
	setPassOwned: (self: Monetization, ctx: PlayerContext, role: string, owned: boolean) -> (boolean, string?),
	clearPlayer: (self: Monetization, ctx: PlayerContext) -> (),
	modifierSource: (self: Monetization) -> Modifiers.Source,
}

local GRANTED: Decision = "PurchaseGranted"
local NOT_PROCESSED: Decision = "NotProcessedYet"
local ROLE_PATTERN = "^[a-z][a-z0-9_]*$"
local DEFAULT_FIELD = "purchases"
local DEFAULT_PERKS_FIELD = "perks"
local DEFAULT_MAX_REMEMBERED = 50

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function isPositiveInteger(value: any): boolean
	return isFinite(value) and value > 0 and value == math.floor(value)
end

local Monetization = {}

function Monetization.new(options: Options): Monetization
	assert(type(options.getProfile) == "function", "Monetization: getProfile must be a function")
	assert(options.session ~= nil, "Monetization: session must be set")
	assert(options.economy ~= nil, "Monetization: economy must be set")
	assert(type(options.ownsPass) == "function", "Monetization: ownsPass must be a function")
	assert(type(options.products) == "table", "Monetization: products must be a table")
	for productId, product in options.products do
		local where = "Monetization: product " .. tostring(productId)
		assert(isPositiveInteger(productId), where .. ": id must be a positive integer")
		assert(
			type(product.role) == "string" and string.match(product.role, ROLE_PATTERN) ~= nil,
			where .. ": bad role"
		)
		assert(type(product.rewards) == "table" and #product.rewards >= 1, where .. ": needs at least one reward")
		for _, reward in product.rewards do
			if reward.type == "coins" then
				assert(isPositiveInteger(reward.amount), where .. ": coins amount must be a whole number > 0")
			elseif reward.type == "perk" then
				assert(type(reward.perkId) == "string" and reward.perkId ~= "", where .. ": perkId must be set")
			else
				error(where .. ": unknown reward type " .. tostring(reward.type))
			end
		end
	end
	assert(type(options.passes) == "table", "Monetization: passes must be a table")
	for role, pass in options.passes do
		local where = "Monetization: pass " .. tostring(role)
		assert(type(role) == "string" and string.match(role, ROLE_PATTERN) ~= nil, where .. ": bad role")
		assert(isPositiveInteger(pass.passId), where .. ": passId must be a positive integer")
		assert(type(pass.effects) == "table", where .. ": effects must be a table")
		for stat, effect in pass.effects do
			assert(type(stat) == "string" and type(effect) == "table", where .. ": invalid effect")
			assert(effect.add == nil or isFinite(effect.add), where .. ": add must be finite")
			assert(effect.mul == nil or (isFinite(effect.mul) and effect.mul >= 0), where .. ": mul must be >= 0")
		end
	end
	local field = options.field or DEFAULT_FIELD
	local perksField = options.perksField or DEFAULT_PERKS_FIELD
	local maxRemembered = options.maxRemembered or DEFAULT_MAX_REMEMBERED
	assert(isPositiveInteger(maxRemembered), "Monetization: maxRemembered must be a positive integer")

	local getProfile = options.getProfile
	local session = options.session
	local economy = options.economy
	local products = options.products
	local passes = options.passes
	local ownsPass = options.ownsPass
	local onPurchase = options.onPurchase

	local passRoles: { string } = {}
	for role in passes do
		table.insert(passRoles, role)
	end
	table.sort(passRoles)

	-- Kaeufe, deren Speicherung gerade laeuft (dieselbe Quittung parallel wird nicht doppelt bearbeitet).
	local pending: { [string]: boolean } = {}
	-- Pass-Besitz pro Spieler, nur im Speicher.
	local ownedPasses: { [number]: { [string]: boolean } } = {}

	-- PurchaseId-Liste (neueste vorne). Fehlt das Feld, wird es angelegt; nil = vorhandener Wert ungueltig.
	local function purchaseList(profile: Profile): { string }?
		local stored = profile[field]
		if stored == nil then
			stored = {}
			profile[field] = stored
			return stored
		end
		if type(stored) ~= "table" then
			return nil
		end
		local count = 0
		for _ in stored do
			count += 1
		end
		if count ~= #stored then
			return nil
		end
		for _, purchaseId in stored do
			if type(purchaseId) ~= "string" or purchaseId == "" then
				return nil
			end
		end
		return stored
	end

	-- Perk-Set { [perkId]: true }. Fehlt das Feld, wird es angelegt; nil = vorhandener Wert ungueltig.
	local function perkSet(profile: Profile): { [string]: boolean }?
		local stored = profile[perksField]
		if stored == nil then
			stored = {}
			profile[perksField] = stored
			return stored
		end
		if type(stored) ~= "table" then
			return nil
		end
		for perkId, value in stored do
			if type(perkId) ~= "string" or perkId == "" or value ~= true then
				return nil
			end
		end
		return stored
	end

	-- Bucht gutgeschriebene Coins zurueck; reicht das Guthaben nicht, wird auf 0 gesetzt.
	local function rollbackCoins(ctx: PlayerContext, amount: number, purchaseId: string)
		if amount <= 0 then
			return
		end
		local ok, err = economy:debit(ctx, amount, "purchase_rollback")
		if ok then
			return
		end
		if err == "INSUFFICIENT_FUNDS" then
			local balance = economy:balance(ctx)
			if balance ~= nil and balance > 0 then
				economy:debit(ctx, balance, "purchase_rollback")
			end
			warn(string.format("[Monetization] rollback of %s: balance too low, set to 0", purchaseId))
		else
			warn(
				string.format(
					"[Monetization] rollback of %s: coins could not be debited (%s)",
					purchaseId,
					tostring(err)
				)
			)
		end
	end

	local monetization: Monetization = {
		processReceipt = function(_self, receipt: Receipt): Decision
			if
				type(receipt) ~= "table"
				or type(receipt.PurchaseId) ~= "string"
				or receipt.PurchaseId == ""
				or not isPositiveInteger(receipt.PlayerId)
				or type(receipt.ProductId) ~= "number"
			then
				warn("[Monetization] invalid receipt")
				return NOT_PROCESSED
			end
			local product = products[receipt.ProductId]
			if product == nil then
				warn("[Monetization] unknown product " .. tostring(receipt.ProductId))
				return NOT_PROCESSED
			end
			local purchaseId = receipt.PurchaseId
			if pending[purchaseId] then
				return NOT_PROCESSED
			end
			local ctx: PlayerContext = { userId = receipt.PlayerId }
			local profile = getProfile(ctx)
			if profile == nil then
				return NOT_PROCESSED
			end
			local purchases = purchaseList(profile)
			local perks = perkSet(profile)
			if purchases == nil or perks == nil then
				warn("[Monetization] corrupt purchases or perks field for user " .. tostring(ctx.userId))
				return NOT_PROCESSED
			end
			if table.find(purchases, purchaseId) ~= nil then
				return GRANTED
			end

			-- Rewards im Speicher anwenden und dabei genau festhalten, was sich geaendert hat.
			local creditedCoins = 0
			local grantedPerks: { string } = {}
			local function rollbackRewards()
				rollbackCoins(ctx, creditedCoins, purchaseId)
				for _, perkId in grantedPerks do
					perks[perkId] = nil
				end
			end
			for _, reward in product.rewards do
				if reward.type == "coins" then
					local before = economy:balance(ctx)
					local ok, err = economy:credit(ctx, reward.amount :: number, "purchase")
					local after = economy:balance(ctx)
					if not ok or before == nil or after == nil then
						rollbackRewards()
						warn(string.format("[Monetization] reward for %s failed: %s", purchaseId, tostring(err)))
						return NOT_PROCESSED
					end
					creditedCoins += after - before
				else
					local perkId = reward.perkId :: string
					if perks[perkId] ~= true then
						perks[perkId] = true
						table.insert(grantedPerks, perkId)
					end
				end
			end
			table.insert(purchases, 1, purchaseId)
			local dropped: { string } = {}
			while #purchases > maxRemembered do
				table.insert(dropped, table.remove(purchases) :: string)
			end

			pending[purchaseId] = true
			local saved, saveErr = session:save(ctx)
			pending[purchaseId] = nil
			if not saved then
				rollbackRewards()
				local index = table.find(purchases, purchaseId)
				if index ~= nil then
					table.remove(purchases, index)
				end
				for i = #dropped, 1, -1 do
					table.insert(purchases, dropped[i])
				end
				warn(string.format("[Monetization] save of %s failed: %s", purchaseId, tostring(saveErr)))
				return NOT_PROCESSED
			end

			if onPurchase then
				local ok, err = pcall(onPurchase, ctx, { role = product.role, purchaseId = purchaseId })
				if not ok then
					warn("[Monetization] onPurchase failed: " .. tostring(err))
				end
			end
			return GRANTED
		end,

		hasPerk = function(_self, ctx: PlayerContext, perkId: string): boolean
			local profile = getProfile(ctx)
			if profile == nil then
				return false
			end
			local perks = perkSet(profile)
			return perks ~= nil and perks[perkId] == true
		end,

		refreshPasses = function(_self, ctx: PlayerContext)
			local owned: { [string]: boolean } = {}
			for _, role in passRoles do
				local ok, result = pcall(ownsPass, ctx.userId, passes[role].passId)
				if not ok then
					warn(string.format("[Monetization] ownsPass for %s failed: %s", role, tostring(result)))
				elseif result == true then
					owned[role] = true
				end
			end
			ownedPasses[ctx.userId] = owned
		end,

		setPassOwned = function(_self, ctx: PlayerContext, role: string, owned: boolean): (boolean, string?)
			if passes[role] == nil then
				return false, "UNKNOWN_PASS"
			end
			local cache = ownedPasses[ctx.userId] or {}
			cache[role] = if owned then true else nil
			ownedPasses[ctx.userId] = cache
			return true, nil
		end,

		clearPlayer = function(_self, ctx: PlayerContext)
			ownedPasses[ctx.userId] = nil
		end,

		modifierSource = function(_self): Modifiers.Source
			return function(ctx: PlayerContext): { [string]: Modifiers.Effect }
				local effects: { [string]: Modifiers.Effect } = {}
				local owned = ownedPasses[ctx.userId]
				if owned == nil then
					return effects
				end
				for _, role in passRoles do
					if owned[role] then
						for stat, effect in passes[role].effects do
							local combined = effects[stat] or {}
							if effect.add ~= nil then
								combined.add = (combined.add or 0) + effect.add
							end
							if effect.mul ~= nil then
								combined.mul = (combined.mul or 1) * effect.mul
							end
							effects[stat] = combined
						end
					end
				end
				return effects
			end
		end,
	}
	return monetization
end

return Monetization
