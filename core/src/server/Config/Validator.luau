--!strict
-- Prueft eine Game-Config gegen das Schema und sammelt alle Fehler (bricht nicht beim ersten ab, wirft nie).
-- Geprueft wird auch alles, was die Modul-Konstruktoren per assert pruefen wuerden, damit eine gueltige Config
-- beim Zusammensetzen (GameServer.compose) nie einen assert ausloest.
--
-- Codes: MISSING_FIELD, WRONG_TYPE, INVALID_ID, INVALID_VALUE (nicht endlich, keine ganze Zahl, negativ, zu
-- gross), DUPLICATE_ID, NOT_POSITIVE, COSTS_NOT_INCREASING, UNKNOWN_REFERENCE, UNREACHABLE_ZONE, MISSING_ASSET,
-- EMPTY_REWARDS, MISSING_TEXT, UNKNOWN_ENUM, MISSING_REMOTE, VALIDATOR_ERROR (interner Fehler, sollte nie
-- auftreten). path z. B. "upgrades.range.levels[2].cost".
local Schema = require(script.Parent.Schema)

export type ValidationError = {
	path: string,
	code: string,
	message: string,
}

export type Result = {
	ok: boolean,
	errors: { ValidationError },
}

type NumberRule = {
	integer: boolean?,
	positive: boolean?, -- > 0
	nonNegative: boolean?, -- >= 0
	max: number?,
}

local MAX_COINS = 1e12

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function sortedKeys(map: { [any]: any }): { any }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return keys
end

local Validator = {}

function Validator.validate(config: any): Result
	local errors: { ValidationError } = {}

	local function add(path: string, code: string, message: string)
		table.insert(errors, { path = path, code = code, message = message })
	end

	local function join(path: string, key: any): string
		return if path == "" then tostring(key) else path .. "." .. tostring(key)
	end

	-- Prueft, dass value eine Tabelle ist. Liefert die Tabelle oder nil.
	local function tbl(path: string, value: any): { [any]: any }?
		if value == nil then
			add(path, "MISSING_FIELD", path .. " is missing")
			return nil
		end
		if type(value) ~= "table" then
			add(path, "WRONG_TYPE", path .. " must be a table")
			return nil
		end
		return value
	end

	local function num(path: string, value: any, rule: NumberRule): boolean
		if value == nil then
			add(path, "MISSING_FIELD", path .. " is missing")
			return false
		end
		if type(value) ~= "number" then
			add(path, "WRONG_TYPE", path .. " must be a number")
			return false
		end
		if not isFinite(value) then
			add(path, "INVALID_VALUE", path .. " must be finite")
			return false
		end
		if rule.integer and value ~= math.floor(value) then
			add(path, "INVALID_VALUE", path .. " must be a whole number")
			return false
		end
		if rule.positive and value <= 0 then
			add(path, "NOT_POSITIVE", path .. " must be > 0")
			return false
		end
		if rule.nonNegative and value < 0 then
			add(path, "INVALID_VALUE", path .. " must be >= 0")
			return false
		end
		if rule.max ~= nil and value > rule.max then
			add(path, "INVALID_VALUE", path .. " must be <= " .. tostring(rule.max))
			return false
		end
		return true
	end

	local function str(path: string, value: any): boolean
		if value == nil or value == "" then
			add(path, "MISSING_FIELD", path .. " is missing")
			return false
		end
		if type(value) ~= "string" then
			add(path, "WRONG_TYPE", path .. " must be a string")
			return false
		end
		return true
	end

	local function id(path: string, value: any): boolean
		if not str(path, value) then
			return false
		end
		if string.match(value, Schema.ID_PATTERN) == nil then
			add(path, "INVALID_ID", path .. " must match " .. Schema.ID_PATTERN)
			return false
		end
		return true
	end

	-- Prueft die Schluessel einer ID-Map.
	local function idKey(path: string, key: any): boolean
		if type(key) ~= "string" or string.match(key, Schema.ID_PATTERN) == nil then
			add(
				join(path, key),
				"INVALID_ID",
				"id " .. tostring(key) .. " in " .. path .. " must match " .. Schema.ID_PATTERN
			)
			return false
		end
		return true
	end

	local function enum(path: string, value: any, allowed: { string }): boolean
		if not str(path, value) then
			return false
		end
		if table.find(allowed, value) == nil then
			add(path, "UNKNOWN_ENUM", path .. " must be one of " .. table.concat(allowed, ", "))
			return false
		end
		return true
	end

	local function check()
		if type(config) ~= "table" then
			add("", "WRONG_TYPE", "config must be a table")
			return
		end

		-- texts zuerst, damit nameKeys dagegen geprueft werden koennen.
		local texts = tbl("texts", config.texts) or {}
		for _, key in sortedKeys(texts) do
			if type(key) ~= "string" or key == "" then
				add("texts", "INVALID_ID", "text keys must be non-empty strings")
			elseif type(texts[key]) ~= "string" then
				add("texts." .. key, "WRONG_TYPE", "texts." .. key .. " must be a string")
			end
		end
		local function text(path: string, key: any)
			if str(path, key) and type(texts[key]) ~= "string" then
				add(path, "MISSING_TEXT", path .. " refers to missing text " .. tostring(key))
			end
		end

		-- game
		local game = tbl("game", config.game)
		if game then
			id("game.id", game.id)
			str("game.configVersion", game.configVersion)
			num("game.startCoins", game.startCoins, { integer = true, nonNegative = true, max = MAX_COINS })
			num("game.schemaVersion", game.schemaVersion, { integer = true, positive = true })
			local base = tbl("game.base", game.base)
			if base then
				num("game.base.range", base.range, { nonNegative = true })
				num("game.base.capacity", base.capacity, { positive = true })
				num("game.base.sellFactor", base.sellFactor, { positive = true })
			end
		end

		-- upgrades (vor zones, weil upgradeLevel-Bedingungen darauf verweisen)
		local upgrades = tbl("upgrades", config.upgrades) or {}
		for _, dimension in sortedKeys(upgrades) do
			local path = join("upgrades", dimension)
			if idKey("upgrades", dimension) then
				local upgrade = tbl(path, upgrades[dimension])
				if upgrade then
					enum(path .. ".stat", upgrade.stat, Schema.STATS)
					text(path .. ".nameKey", upgrade.nameKey)
					local levels = tbl(path .. ".levels", upgrade.levels)
					if levels and #levels == 0 then
						add(path .. ".levels", "MISSING_FIELD", path .. ".levels needs at least one level")
					elseif levels then
						local previousCost: number? = nil
						for index, level in levels do
							local levelPath = string.format("%s.levels[%d]", path, index)
							if tbl(levelPath, level) then
								local costPath = levelPath .. ".cost"
								if num(costPath, level.cost, { integer = true, positive = true }) then
									if previousCost ~= nil and level.cost <= previousCost then
										add(
											costPath,
											"COSTS_NOT_INCREASING",
											costPath .. " must be greater than the previous cost"
										)
									end
									previousCost = level.cost
								end
								if level.add == nil and level.mul == nil then
									add(levelPath, "MISSING_FIELD", levelPath .. " needs add or mul")
								end
								if level.add ~= nil then
									num(levelPath .. ".add", level.add, {})
								end
								if level.mul ~= nil then
									num(levelPath .. ".mul", level.mul, { nonNegative = true })
								end
							end
						end
					end
				end
			end
		end

		-- zones
		local zones = tbl("zones", config.zones) or {}
		local zoneIds = sortedKeys(zones)
		if config.zones ~= nil and #zoneIds == 0 then
			add("zones", "MISSING_FIELD", "zones needs at least one zone")
		end
		local orders: { [number]: string } = {}
		local validZones: { string } = {}
		for _, zoneId in zoneIds do
			local path = join("zones", zoneId)
			if idKey("zones", zoneId) then
				local zone = tbl(path, zones[zoneId])
				if zone then
					if num(path .. ".order", zone.order, { integer = true }) then
						if orders[zone.order] ~= nil then
							add(
								path .. ".order",
								"DUPLICATE_ID",
								"order " .. zone.order .. " is also used by " .. orders[zone.order]
							)
						else
							orders[zone.order] = zoneId
							table.insert(validZones, zoneId)
						end
					end
					num(path .. ".density", zone.density, { integer = true, nonNegative = true })
					num(path .. ".respawnSeconds", zone.respawnSeconds, { nonNegative = true })
					text(path .. ".nameKey", zone.nameKey)
					tbl(path .. ".condition", zone.condition)
				end
			end
		end
		table.sort(validZones, function(a: string, b: string): boolean
			return zones[a].order < zones[b].order
		end)
		-- Erreichbarkeit: Startzone "always", jede weitere Zone eine bekannte Bedingung mit gueltigen Parametern.
		for rank, zoneId in validZones do
			local condition = zones[zoneId].condition
			local path = join("zones", zoneId) .. ".condition"
			if type(condition) == "table" then
				local conditionType = condition.type
				if rank == 1 then
					if conditionType ~= "always" then
						add(path .. ".type", "UNREACHABLE_ZONE", "the zone with the lowest order must use always")
					end
				elseif conditionType == "always" then
					add(path .. ".type", "UNREACHABLE_ZONE", "only the zone with the lowest order may use always")
				elseif conditionType == "coinsAtLeast" then
					num(path .. ".amount", condition.amount, { integer = true, positive = true })
				elseif conditionType == "purchase" then
					num(path .. ".cost", condition.cost, { integer = true, positive = true })
				elseif conditionType == "upgradeLevel" then
					local dimension = condition.dimension
					if str(path .. ".dimension", dimension) then
						local upgrade = upgrades[dimension]
						if type(upgrade) ~= "table" then
							add(
								path .. ".dimension",
								"UNKNOWN_REFERENCE",
								"unknown upgrade dimension " .. tostring(dimension)
							)
						elseif num(path .. ".level", condition.level, { integer = true, positive = true }) then
							local levelCount = if type(upgrade.levels) == "table" then #upgrade.levels else 0
							if condition.level > levelCount then
								add(
									path .. ".level",
									"UNREACHABLE_ZONE",
									"level " .. condition.level .. " exceeds the upgrade levels"
								)
							end
						end
					end
				else
					add(path .. ".type", "UNREACHABLE_ZONE", "unknown condition type " .. tostring(conditionType))
				end
			end
		end

		-- items
		local items = tbl("items", config.items) or {}
		local itemsPerZone: { [string]: number } = {}
		for _, itemId in sortedKeys(items) do
			local path = join("items", itemId)
			if idKey("items", itemId) then
				local item = tbl(path, items[itemId])
				if item then
					if id(path .. ".zoneId", item.zoneId) then
						if type(zones[item.zoneId]) ~= "table" then
							add(path .. ".zoneId", "UNKNOWN_REFERENCE", "unknown zone " .. item.zoneId)
						else
							itemsPerZone[item.zoneId] = (itemsPerZone[item.zoneId] or 0) + 1
						end
					end
					num(path .. ".spawnWeight", item.spawnWeight, { positive = true })
					num(path .. ".price", item.price, { integer = true, positive = true })
					if item.asset == nil or item.asset == "" then
						add(path .. ".asset", "MISSING_ASSET", path .. " has no asset reference")
					else
						id(path .. ".asset", item.asset)
					end
					text(path .. ".nameKey", item.nameKey)
					if item.rarity ~= nil then
						enum(path .. ".rarity", item.rarity, Schema.RARITIES)
					end
				end
			end
		end
		for _, zoneId in validZones do
			local density = zones[zoneId].density
			if isFinite(density) and density > 0 and (itemsPerZone[zoneId] or 0) == 0 then
				add(join("zones", zoneId) .. ".density", "UNREACHABLE_ZONE", "zone has density > 0 but no items")
			end
		end

		-- collect
		local collect = tbl("collect", config.collect)
		if collect then
			enum("collect.type", collect.type, Schema.COLLECT_TYPES)
			local params = tbl("collect.params", collect.params)
			if params and params.radius ~= nil then
				num("collect.params.radius", params.radius, { nonNegative = true })
			end
			num("collect.rangeTolerance", collect.rangeTolerance, { nonNegative = true })
			local rateLimit = tbl("collect.rateLimit", collect.rateLimit)
			if rateLimit then
				num("collect.rateLimit.maxItems", rateLimit.maxItems, { integer = true, positive = true })
				num("collect.rateLimit.windowSeconds", rateLimit.windowSeconds, { positive = true })
			end
		end

		-- sell
		local sell = tbl("sell", config.sell)
		if sell then
			enum("sell.trigger", sell.trigger, Schema.SELL_TRIGGERS)
		end

		-- products
		local products = tbl("products", config.products) or {}
		local productIds: { [number]: string } = {}
		for _, role in sortedKeys(products) do
			local path = join("products", role)
			if idKey("products", role) then
				local product = tbl(path, products[role])
				if product then
					if num(path .. ".productId", product.productId, { integer = true, positive = true }) then
						if productIds[product.productId] ~= nil then
							add(
								path .. ".productId",
								"DUPLICATE_ID",
								"productId is also used by " .. productIds[product.productId]
							)
						else
							productIds[product.productId] = role
						end
					end
					local rewards = tbl(path .. ".rewards", product.rewards)
					if rewards and #rewards == 0 then
						add(path .. ".rewards", "EMPTY_REWARDS", path .. " has no rewards")
					elseif rewards then
						for index, reward in rewards do
							local rewardPath = string.format("%s.rewards[%d]", path, index)
							if
								tbl(rewardPath, reward)
								and enum(rewardPath .. ".type", reward.type, Schema.REWARD_TYPES)
							then
								if reward.type == "coins" then
									num(rewardPath .. ".amount", reward.amount, { integer = true, positive = true })
								else
									id(rewardPath .. ".perkId", reward.perkId)
								end
							end
						end
					end
				end
			end
		end

		-- passes
		local passes = tbl("passes", config.passes) or {}
		local passIds: { [number]: string } = {}
		for _, role in sortedKeys(passes) do
			local path = join("passes", role)
			if idKey("passes", role) then
				local pass = tbl(path, passes[role])
				if pass then
					if num(path .. ".passId", pass.passId, { integer = true, positive = true }) then
						if passIds[pass.passId] ~= nil then
							add(path .. ".passId", "DUPLICATE_ID", "passId is also used by " .. passIds[pass.passId])
						else
							passIds[pass.passId] = role
						end
					end
					local effects = tbl(path .. ".effects", pass.effects)
					if effects then
						for _, stat in sortedKeys(effects) do
							local effectPath = join(path .. ".effects", stat)
							if enum(effectPath, stat, Schema.STATS) then
								local effect = tbl(effectPath, effects[stat])
								if effect then
									if effect.add ~= nil then
										num(effectPath .. ".add", effect.add, {})
									end
									if effect.mul ~= nil then
										num(effectPath .. ".mul", effect.mul, { nonNegative = true })
									end
								end
							end
						end
					end
				end
			end
		end

		-- remotes
		local remotes = tbl("remotes", config.remotes) or {}
		for _, name in Schema.REMOTES do
			local path = join("remotes", name)
			local remote = remotes[name]
			if remote == nil then
				add(path, "MISSING_REMOTE", "remote " .. name .. " needs a rate limit")
			elseif tbl(path, remote) then
				num(path .. ".max", remote.max, { integer = true, positive = true })
				num(path .. ".windowSeconds", remote.windowSeconds, { positive = true })
			end
		end
		for _, name in sortedKeys(remotes) do
			if table.find(Schema.REMOTES, name) == nil then
				add(join("remotes", name), "UNKNOWN_ENUM", "unknown remote " .. tostring(name))
			end
		end

		-- collection (optional)
		if config.collection ~= nil then
			local collection = tbl("collection", config.collection)
			local groups = if collection then tbl("collection.groups", collection.groups) else nil
			if groups then
				local usedEntries: { [string]: boolean } = {}
				local usedItems: { [string]: boolean } = {}
				local usedOrders: { [number]: boolean } = {}
				for _, groupId in sortedKeys(groups) do
					local path = join("collection.groups", groupId)
					local group = groups[groupId]
					if idKey("collection.groups", groupId) and tbl(path, group) then
						if num(path .. ".order", group.order, { integer = true, positive = true }) then
							if usedOrders[group.order] then
								add(
									path .. ".order",
									"DUPLICATE",
									"order " .. tostring(group.order) .. " is used twice"
								)
							end
							usedOrders[group.order] = true
						end
						str(path .. ".nameKey", group.nameKey)
						local entries = tbl(path .. ".entries", group.entries)
						if entries and #entries == 0 then
							add(path .. ".entries", "MISSING_FIELD", path .. ".entries must not be empty")
						end
						for index, entry in entries or {} do
							local entryPath = path .. ".entries." .. tostring(index)
							if tbl(entryPath, entry) and id(entryPath .. ".id", entry.id) then
								if usedEntries[entry.id] then
									add(entryPath .. ".id", "DUPLICATE", "entry " .. entry.id .. " is used twice")
								end
								usedEntries[entry.id] = true
								local itemTypes = tbl(entryPath .. ".itemTypes", entry.itemTypes)
								if itemTypes and #itemTypes == 0 then
									add(entryPath .. ".itemTypes", "MISSING_FIELD", entryPath .. ".itemTypes is empty")
								end
								for _, itemTypeId in itemTypes or {} do
									local itemPath = entryPath .. ".itemTypes"
									if type(config.items) ~= "table" or config.items[itemTypeId] == nil then
										add(itemPath, "UNKNOWN_REFERENCE", "unknown item type " .. tostring(itemTypeId))
									elseif usedItems[itemTypeId] then
										add(itemPath, "DUPLICATE", "item type " .. itemTypeId .. " is used twice")
									end
									usedItems[itemTypeId] = true
								end
							end
						end
						local reward = tbl(path .. ".reward", group.reward)
						if reward then
							if reward.coins ~= nil then
								num(path .. ".reward.coins", reward.coins, { integer = true, nonNegative = true })
							end
							if reward.effects ~= nil and tbl(path .. ".reward.effects", reward.effects) then
								for _, stat in sortedKeys(reward.effects) do
									local effectPath = path .. ".reward.effects." .. stat
									local effect = reward.effects[stat]
									if table.find(Schema.STATS, stat) == nil then
										add(effectPath, "UNKNOWN_ENUM", "unknown stat " .. tostring(stat))
									elseif tbl(effectPath, effect) then
										if effect.add ~= nil then
											num(effectPath .. ".add", effect.add, {})
										end
										if effect.mul ~= nil then
											num(effectPath .. ".mul", effect.mul, { nonNegative = true })
										end
									end
								end
							end
						end
					end
				end
			end
		end

		-- prestige (optional)
		if config.prestige ~= nil then
			local prestige = tbl("prestige", config.prestige)
			if prestige then
				num("prestige.coinsRequired", prestige.coinsRequired, { integer = true, positive = true })
				num("prestige.sellBonusPerLevel", prestige.sellBonusPerLevel, { positive = true })
			end
		end

		-- sim
		local sim = tbl("sim", config.sim)
		if sim then
			num("sim.tripSeconds", sim.tripSeconds, { nonNegative = true })
			num("sim.sellSeconds", sim.sellSeconds, { nonNegative = true })
		end
	end

	local ok, err = pcall(check)
	if not ok then
		add("", "VALIDATOR_ERROR", "validator failed: " .. tostring(err))
	end
	return { ok = #errors == 0, errors = errors }
end

-- Mehrzeilige Zusammenfassung fuer Fehlermeldungen.
function Validator.format(result: Result): string
	local lines = {}
	for _, err in result.errors do
		table.insert(lines, string.format("%s %s: %s", err.code, err.path, err.message))
	end
	return table.concat(lines, "\n")
end

return Validator
