--!strict
-- Rueckweg Server -> Client: schickt jedem Spieler regelmaessig einen Schnappschuss NUR seines eigenen Zustands.
-- Der Schnappschuss dient ausschliesslich der Anzeige; er enthaelt nichts, was der Client zuruecksenden koennte,
-- um einen Wert zu setzen, und nie Daten anderer Spieler, Robux-Preise, Produkt-/Pass-IDs, PurchaseIds oder
-- Funnel-Daten. Erstellt wird er nur mit Lesezugriffen auf die Module.
--
-- markDirty(ctx) merkt vor; flush() sendet je vorgemerktem Spieler hoechstens einen Schnappschuss und pro
-- Spieler hoechstens einen pro minIntervalSeconds (spaeter Vorgemerkte bleiben vorgemerkt). send laeuft in pcall;
-- bei Fehler bleibt der Spieler vorgemerkt. Profil nicht geladen oder Wert beschaedigt: kein Schnappschuss,
-- Spieler bleibt vorgemerkt, gedrosselte Warnung.
--
-- Schnappschuss: { seq, coins, capacity, inventoryCount, inventory = { [itemTypeId] = count }, range, sellFactor,
-- upgrades = { [dimension] = { level, maxLevel, nextCost? } }, zones = { [zoneId] = { unlocked, order } },
-- items = { { instanceId, itemTypeId, zoneId, position } } }. seq steigt pro Spieler streng.
local Log = require(script.Parent.Parent.shared.Log)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)

type PlayerContext = PlayerContext.PlayerContext

export type UpgradeState = {
	level: number,
	maxLevel: number,
	nextCost: number?,
}

export type ZoneState = {
	unlocked: boolean,
	order: number,
}

export type ItemState = {
	instanceId: string,
	itemTypeId: string,
	zoneId: string,
	position: Vector3,
}

export type Snapshot = {
	seq: number,
	coins: number,
	capacity: number,
	inventoryCount: number,
	inventory: { [string]: number },
	range: number,
	sellFactor: number,
	upgrades: { [string]: UpgradeState },
	zones: { [string]: ZoneState },
	items: { ItemState },
}

export type Options = {
	modules: any, -- GameServer.Modules (nur Lesezugriffe)
	config: any, -- validierte Game-Config
	send: (ctx: PlayerContext, snapshot: Snapshot) -> (),
	clock: (() -> number)?,
	minIntervalSeconds: number?,
	log: Log.Log?,
}

export type StateSync = {
	markDirty: (self: StateSync, ctx: PlayerContext) -> (),
	flush: (self: StateSync) -> number,
	forget: (self: StateSync, ctx: PlayerContext) -> (),
	snapshot: (self: StateSync, ctx: PlayerContext) -> Snapshot?,
}

type PlayerState = {
	seq: number,
	lastSentAt: number?,
}

local DEFAULT_MIN_INTERVAL_SECONDS = 0.2

local StateSync = {}

function StateSync.new(options: Options): StateSync
	assert(options.modules ~= nil and options.config ~= nil, "StateSync: modules and config must be set")
	assert(type(options.send) == "function", "StateSync: send must be a function")
	local modules = options.modules
	local config = options.config
	local send = options.send
	local clock: () -> number = options.clock or function()
		return DateTime.now().UnixTimestampMillis / 1000
	end
	local minInterval = options.minIntervalSeconds or DEFAULT_MIN_INTERVAL_SECONDS
	local log = options.log or Log.new({ clock = clock })

	local dimensions: { string } = {}
	for dimension in config.upgrades do
		table.insert(dimensions, dimension)
	end
	table.sort(dimensions)

	local dirty: { [number]: PlayerContext } = {}
	local players: { [number]: PlayerState } = {}

	-- Baut den Schnappschuss ohne seq; nil, wenn das Profil nicht geladen oder ein Wert beschaedigt ist.
	local function build(ctx: PlayerContext): ({ [string]: any }?, string?)
		local coins = modules.economy:balance(ctx)
		local inventory = modules.inventory:contents(ctx)
		local inventoryCount = modules.inventory:count(ctx)
		if coins == nil or inventory == nil or inventoryCount == nil then
			return nil, if modules.session:get(ctx) == nil then "not loaded" else "corrupt economy or inventory"
		end
		local upgrades: { [string]: UpgradeState } = {}
		for _, dimension in dimensions do
			local level = modules.upgrades:level(ctx, dimension)
			if level == nil then
				return nil, "corrupt upgrades"
			end
			upgrades[dimension] = {
				level = level,
				maxLevel = #config.upgrades[dimension].levels,
				nextCost = modules.upgrades:nextCost(ctx, dimension),
			}
		end
		local zones: { [string]: ZoneState } = {}
		for zoneId, zone in config.zones do
			zones[zoneId] = { unlocked = modules.zones:isUnlocked(ctx, zoneId), order = zone.order }
		end
		local items: { ItemState } = {}
		for _, instance in modules.collecting:instances(ctx) or {} do
			table.insert(items, {
				instanceId = instance.instanceId,
				itemTypeId = instance.itemTypeId,
				zoneId = instance.zoneId,
				position = instance.position,
			})
		end
		return {
			coins = coins,
			capacity = math.floor(modules.modifiers:value(ctx, "capacity")),
			inventoryCount = inventoryCount,
			inventory = inventory,
			range = modules.modifiers:value(ctx, "range"),
			sellFactor = modules.modifiers:value(ctx, "sellFactor"),
			upgrades = upgrades,
			zones = zones,
			items = items,
		},
			nil
	end

	local function stateOf(userId: number): PlayerState
		local state = players[userId]
		if state == nil then
			state = { seq = 0 }
			players[userId] = state
		end
		return state
	end

	local sync: StateSync = {
		markDirty = function(_self, ctx: PlayerContext)
			dirty[ctx.userId] = ctx
		end,

		-- Liefert die Zahl der gesendeten Schnappschuesse.
		flush = function(_self): number
			local now = clock()
			local userIds = {}
			for userId in dirty do
				table.insert(userIds, userId)
			end
			table.sort(userIds)
			local sent = 0
			for _, userId in userIds do
				local ctx = dirty[userId]
				local state = stateOf(userId)
				if state.lastSentAt == nil or now - state.lastSentAt >= minInterval then
					local data, problem = build(ctx)
					if data == nil then
						log:warnThrottled(
							"build:" .. tostring(userId),
							string.format("[StateSync] no snapshot for %d: %s", userId, tostring(problem))
						)
					else
						data.seq = state.seq + 1
						local ok, err = pcall(send, ctx, data :: any)
						if ok then
							state.seq = data.seq
							state.lastSentAt = now
							dirty[userId] = nil
							sent += 1
						else
							log:warnThrottled("send", "[StateSync] send failed: " .. tostring(err))
						end
					end
				end
			end
			return sent
		end,

		forget = function(_self, ctx: PlayerContext)
			dirty[ctx.userId] = nil
			players[ctx.userId] = nil
		end,

		-- Nur lesend, ohne seq-Vergabe und ohne Versand (fuer Tests und Diagnose).
		snapshot = function(_self, ctx: PlayerContext): Snapshot?
			local data = build(ctx)
			if data == nil then
				return nil
			end
			data.seq = stateOf(ctx.userId).seq
			return data :: any
		end,
	}
	return sync
end

return StateSync
