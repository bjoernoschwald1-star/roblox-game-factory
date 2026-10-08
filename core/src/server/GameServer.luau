--!strict
-- Setzt ein Game allein aus seiner Config und injizierten Diensten zusammen. Keine Roblox-Dienste, keine
-- Schleifen oder Timer: Wann refillAll und autosaveAll laufen und wie Spieler, Remotes und Kaeufe hereinkommen,
-- entscheidet die spaetere Engine-Anbindung.
--
-- compose validiert zuerst; eine ungueltige Config ist ein Programmierfehler beim Start (error mit allen
-- Meldungen). Die Config wird kopiert und nie veraendert.
--
-- Remotes (fest): collect() ohne Argumente (Position kommt vom Server ueber services.getPosition, nie vom
-- Client), sell(), buyUpgrade(dimension), unlockZone(zoneId), prestige(). Rate Limits aus config.remotes.
-- prestige wirkt nur mit config.prestige (sonst ignoriert): Reset ueber Prestige, danach werden die Items des
-- Spielers neu verteilt (nur freie Zonen) und das Profil sofort gespeichert (Fehler: Autosave holt nach).
-- Analytics: onCollected -> first_collect, collect mit FULL -> inventory_full, onSold -> first_sell,
-- onUpgraded -> first_upgrade, onUnlocked -> zone_unlock (zoneIndex = Rang nach order, Startzone = 1),
-- onPurchase -> purchase_success (role).
-- Zustand zum Client (optional, services.sendState): StateSync merkt Spieler vor nach Join, erfolgreichem
-- dispatch, refillAll mit neuen Items, gewaehrtem Kauf und setPassOwned; flushState sendet die Schnappschuesse.
local Analytics = require(script.Parent.Analytics)
local Collecting = require(script.Parent.Collecting)
local Economy = require(script.Parent.Economy)
local Inventory = require(script.Parent.Inventory)
local Log = require(script.Parent.Parent.shared.Log)
local Modifiers = require(script.Parent.Modifiers)
local Monetization = require(script.Parent.Monetization)
local PlayerContext = require(script.Parent.Parent.shared.PlayerContext)
local PlayerSession = require(script.Parent.PlayerSession)
local Prestige = require(script.Parent.Prestige)
local ProfileStore = require(script.Parent.ProfileStore)
local Radius = require(script.Parent.CollectTypes.Radius)
local RemoteGateway = require(script.Parent.RemoteGateway)
local Schema = require(script.Parent.Config.Schema)
local Selling = require(script.Parent.Selling)
local StateSync = require(script.Parent.StateSync)
local StorageAdapter = require(script.Parent.Storage.StorageAdapter)
local TableCopy = require(script.Parent.Parent.shared.TableCopy)
local Upgrades = require(script.Parent.Upgrades)
local Validator = require(script.Parent.Config.Validator)
local Zones = require(script.Parent.Zones)

type PlayerContext = PlayerContext.PlayerContext

export type Services = {
	storage: StorageAdapter.StorageAdapter,
	dataStoreKeyPrefix: string,
	serverId: string,
	clock: () -> number,
	sleep: ((seconds: number) -> ())?, -- Warten des ProfileStore (Retry/Lock); ohne Angabe task.wait
	rng: Random,
	spawnPosition: (zoneId: string, rng: Random) -> Vector3,
	getPosition: (ctx: PlayerContext) -> Vector3?,
	canSell: (ctx: PlayerContext) -> boolean,
	ownsPass: (userId: number, passId: number) -> boolean,
	analyticsSink: (eventName: string, fields: Analytics.Fields) -> (),
	onLoadFailed: (ctx: PlayerContext, state: ProfileStore.LoadState, err: string?) -> (),
	log: Log.Log?,
	-- Optional: Rueckweg zum Client. Gesetzt -> StateSync markiert nach Join, erfolgreichem dispatch, Refill mit
	-- neuen Items, gewaehrtem Kauf und Pass-Aenderung; flushState sendet. Nicht gesetzt -> Verhalten wie bisher.
	sendState: ((ctx: PlayerContext, snapshot: StateSync.Snapshot) -> ())?,
}

export type Modules = {
	store: ProfileStore.ProfileStore,
	session: PlayerSession.PlayerSession,
	economy: Economy.Economy,
	inventory: Inventory.Inventory,
	modifiers: Modifiers.Modifiers,
	upgrades: Upgrades.Upgrades,
	zones: Zones.Zones,
	collecting: Collecting.Collecting,
	selling: Selling.Selling,
	monetization: Monetization.Monetization,
	analytics: Analytics.Analytics,
	gateway: RemoteGateway.RemoteGateway,
	prestige: Prestige.Prestige?,
}

export type Game = {
	playerJoined: (self: Game, ctx: PlayerContext, source: string) -> ProfileStore.LoadResult,
	playerLeaving: (self: Game, ctx: PlayerContext) -> (boolean, string?),
	dispatch: (self: Game, ctx: PlayerContext, remoteName: string, ...any) -> (boolean, string?),
	refillAll: (self: Game) -> (),
	autosaveAll: (self: Game) -> PlayerSession.SaveReport,
	shutdown: (self: Game) -> PlayerSession.SaveReport,
	processReceipt: (self: Game, receipt: Monetization.Receipt) -> Monetization.Decision,
	setPassOwned: (self: Game, ctx: PlayerContext, role: string, owned: boolean) -> (boolean, string?),
	flushState: (self: Game) -> number,
	modules: Modules,
}

local GameServer = {}

function GameServer.compose(sourceConfig: Schema.GameConfig, services: Services): Game
	local result = Validator.validate(sourceConfig)
	if not result.ok then
		error("GameServer: invalid config\n" .. Validator.format(result), 0)
	end
	assert(type(services) == "table", "GameServer: services must be set")
	for _, name in
		{
			"clock",
			"spawnPosition",
			"getPosition",
			"canSell",
			"ownsPass",
			"analyticsSink",
			"onLoadFailed",
		}
	do
		assert(type((services :: any)[name]) == "function", "GameServer: services." .. name .. " must be a function")
	end
	assert(services.storage ~= nil and services.rng ~= nil, "GameServer: services.storage and services.rng must be set")
	assert(
		services.sendState == nil or type(services.sendState) == "function",
		"GameServer: services.sendState must be a function"
	)

	local config = TableCopy.copy(sourceConfig)
	local log = services.log or Log.new({ clock = services.clock })

	-- Rang jeder Zone nach order (Startzone = 1), fuer zone_unlock.
	local zoneRank: { [string]: number } = {}
	do
		local ordered = {}
		for zoneId in config.zones do
			table.insert(ordered, zoneId)
		end
		table.sort(ordered, function(a: string, b: string): boolean
			return config.zones[a].order < config.zones[b].order
		end)
		for rank, zoneId in ordered do
			zoneRank[zoneId] = rank
		end
	end

	local store = ProfileStore.new({
		storage = services.storage,
		keyPrefix = services.dataStoreKeyPrefix,
		defaults = function()
			return {
				coins = config.game.startCoins,
				inventory = {},
				upgrades = {},
				zones = {},
				purchases = {},
				perks = {},
				funnel = {},
				prestige = 0,
			}
		end,
		schemaVersion = config.game.schemaVersion,
		migrations = {},
		serverId = services.serverId,
		clock = services.clock,
		sleep = services.sleep,
	})
	local session = PlayerSession.new({ store = store, onLoadFailed = services.onLoadFailed })
	local function getProfile(ctx: PlayerContext)
		return session:get(ctx)
	end

	local analytics = Analytics.new({
		gameId = config.game.id,
		configVersion = config.game.configVersion,
		getProfile = getProfile,
		sink = services.analyticsSink,
		clock = services.clock,
		log = log,
	})
	local modifiers = Modifiers.new({ base = config.game.base :: any, log = log })
	local economy = Economy.new({ getProfile = getProfile })
	local inventory = Inventory.new({
		getProfile = getProfile,
		getCapacity = function(ctx)
			return math.floor(modifiers:value(ctx, "capacity"))
		end,
	})

	local dimensions = {}
	for dimension, upgrade in config.upgrades do
		dimensions[dimension] = { stat = upgrade.stat, levels = upgrade.levels }
	end
	local upgrades = Upgrades.new({
		getProfile = getProfile,
		economy = economy,
		dimensions = dimensions,
		onUpgraded = function(ctx)
			analytics:step(ctx, "first_upgrade")
		end,
	})
	modifiers:registerSource("upgrades", upgrades:modifierSource())

	local zoneConditions = {}
	local zoneSpawns = {}
	for zoneId, zone in config.zones do
		zoneConditions[zoneId] = { order = zone.order, condition = zone.condition }
		zoneSpawns[zoneId] = { density = zone.density, respawnSeconds = zone.respawnSeconds }
	end
	local zones = Zones.new({
		getProfile = getProfile,
		zones = zoneConditions,
		economy = economy,
		upgrades = upgrades,
		onUnlocked = function(ctx, event)
			analytics:track(ctx, "zone_unlock", { zoneIndex = zoneRank[event.zoneId] })
		end,
	})

	local itemSpawns = {}
	local prices = {}
	for itemId, item in config.items do
		itemSpawns[itemId] = { zoneId = item.zoneId, spawnWeight = item.spawnWeight }
		prices[itemId] = item.price
	end
	local collecting = Collecting.new({
		items = itemSpawns,
		zones = zoneSpawns,
		inventory = inventory,
		isZoneUnlocked = function(ctx, zoneId)
			return zones:isUnlocked(ctx, zoneId)
		end,
		getRange = function(ctx)
			return modifiers:value(ctx, "range")
		end,
		spawnPosition = services.spawnPosition,
		collectType = Radius,
		collectParams = config.collect.params,
		rangeTolerance = config.collect.rangeTolerance,
		rateLimit = config.collect.rateLimit,
		clock = services.clock,
		rng = services.rng,
		onCollected = function(ctx)
			analytics:step(ctx, "first_collect")
		end,
	})

	local selling = Selling.new({
		inventory = inventory,
		economy = economy,
		modifiers = modifiers,
		prices = prices,
		canSell = services.canSell,
		onSold = function(ctx)
			analytics:step(ctx, "first_sell")
		end,
	})

	local products = {}
	for role, product in config.products do
		products[product.productId] = { role = role, rewards = product.rewards }
	end
	local monetization = Monetization.new({
		getProfile = getProfile,
		session = session,
		economy = economy,
		products = products,
		passes = config.passes,
		ownsPass = services.ownsPass,
		onPurchase = function(ctx, purchase)
			analytics:track(ctx, "purchase_success", { role = purchase.role })
		end,
	})
	modifiers:registerSource("passes", monetization:modifierSource())

	local prestige: Prestige.Prestige? = nil
	if config.prestige ~= nil then
		local created = Prestige.new({
			getProfile = getProfile,
			economy = economy,
			coinsRequired = config.prestige.coinsRequired,
			sellBonusPerLevel = config.prestige.sellBonusPerLevel,
			startCoins = config.game.startCoins,
		})
		modifiers:registerSource("prestige", created:modifierSource())
		prestige = created
	end

	local gateway = RemoteGateway.new({ clock = services.clock, log = log })
	local function limit(name: string): RemoteGateway.RateLimit
		local remote = config.remotes[name]
		return { max = remote.max, windowSeconds = remote.windowSeconds }
	end
	gateway:register("collect", {
		args = {},
		rateLimit = limit("collect"),
		handler = function(ctx)
			local position = services.getPosition(ctx)
			if position == nil then
				return
			end
			local collected = collecting:collect(ctx, position)
			if collected.err == "FULL" then
				analytics:track(ctx, "inventory_full")
			end
		end,
	})
	gateway:register("sell", {
		args = {},
		rateLimit = limit("sell"),
		handler = function(ctx)
			selling:sell(ctx)
		end,
	})
	gateway:register("buyUpgrade", {
		args = {
			{
				type = "id",
				isKnown = function(dimension: string): boolean
					return config.upgrades[dimension] ~= nil
				end,
			},
		},
		rateLimit = limit("buyUpgrade"),
		handler = function(ctx, dimension: string)
			upgrades:purchase(ctx, dimension)
		end,
	})
	gateway:register("unlockZone", {
		args = {
			{
				type = "id",
				isKnown = function(zoneId: string): boolean
					return config.zones[zoneId] ~= nil
				end,
			},
		},
		rateLimit = limit("unlockZone"),
		handler = function(ctx, zoneId: string)
			zones:tryUnlock(ctx, zoneId)
		end,
	})
	gateway:register("prestige", {
		args = {},
		rateLimit = limit("prestige"),
		handler = function(ctx)
			if prestige == nil then
				return
			end
			local ok, err = prestige:reset(ctx)
			if not ok then
				return
			end
			-- Items in nun gesperrten Zonen verschwinden; neu verteilt wird nur in freien Zonen.
			collecting:stopPlayer(ctx)
			collecting:startPlayer(ctx)
			local saved, saveErr = session:save(ctx)
			if not saved then
				log:warnThrottled("prestige_save", "[GameServer] prestige save failed: " .. tostring(saveErr or err))
			end
		end,
	})
	gateway:seal()

	-- Aktive Spieler (erfolgreich geladen) fuer refillAll und shutdown.
	local active: { [number]: PlayerContext } = {}

	local stateSync: StateSync.StateSync? = if services.sendState ~= nil
		then StateSync.new({
			modules = {
				session = session,
				economy = economy,
				inventory = inventory,
				modifiers = modifiers,
				upgrades = upgrades,
				zones = zones,
				collecting = collecting,
				prestige = prestige,
			},
			config = config,
			send = services.sendState,
			clock = services.clock,
			log = log,
		})
		else nil
	local function markDirty(ctx: PlayerContext)
		if stateSync ~= nil then
			stateSync:markDirty(ctx)
		end
	end

	local function cleanup(ctx: PlayerContext)
		active[ctx.userId] = nil
		if stateSync ~= nil then
			stateSync:forget(ctx)
		end
		analytics:sessionEnd(ctx)
		collecting:stopPlayer(ctx)
		monetization:clearPlayer(ctx)
		gateway:clearPlayer(ctx)
	end

	local composed: Game = {
		playerJoined = function(_self, ctx: PlayerContext, source: string): ProfileStore.LoadResult
			local loaded = session:join(ctx)
			if loaded.profile ~= nil and session:get(ctx) ~= nil then
				active[ctx.userId] = ctx
				collecting:startPlayer(ctx)
				monetization:refreshPasses(ctx)
				analytics:sessionStart(ctx, source)
				markDirty(ctx)
			end
			return loaded
		end,

		playerLeaving = function(_self, ctx: PlayerContext): (boolean, string?)
			cleanup(ctx)
			return session:leave(ctx)
		end,

		dispatch = function(_self, ctx: PlayerContext, remoteName: string, ...: any): (boolean, string?)
			local ok, err = gateway:dispatch(ctx, remoteName, ...)
			if ok then
				markDirty(ctx)
			end
			return ok, err
		end,

		refillAll = function(_self)
			for _, ctx in active do
				-- Nur Spieler mit neuen Items vormerken (refill fuegt nur hinzu).
				local before = if stateSync ~= nil then #(collecting:instances(ctx) or {}) else 0
				collecting:refill(ctx)
				if stateSync ~= nil and #(collecting:instances(ctx) or {}) ~= before then
					markDirty(ctx)
				end
			end
		end,

		autosaveAll = function(_self): PlayerSession.SaveReport
			return session:autosaveAll()
		end,

		shutdown = function(_self): PlayerSession.SaveReport
			local players = {}
			for _, ctx in active do
				table.insert(players, ctx)
			end
			for _, ctx in players do
				cleanup(ctx)
			end
			return session:shutdown()
		end,

		processReceipt = function(_self, receipt: Monetization.Receipt): Monetization.Decision
			local decision = monetization:processReceipt(receipt)
			if decision == "PurchaseGranted" and type(receipt) == "table" and type(receipt.PlayerId) == "number" then
				markDirty({ userId = receipt.PlayerId })
			end
			return decision
		end,

		-- Pass-Besitz nach serverseitiger Pruefung aendern (z. B. nach PromptGamePassPurchaseFinished).
		setPassOwned = function(_self, ctx: PlayerContext, role: string, owned: boolean): (boolean, string?)
			local ok, err = monetization:setPassOwned(ctx, role, owned)
			if ok then
				markDirty(ctx)
			end
			return ok, err
		end,

		-- Sendet vorgemerkte Schnappschuesse; ohne services.sendState ein No-op (liefert 0).
		flushState = function(_self): number
			return if stateSync ~= nil then stateSync:flush() else 0
		end,

		modules = {
			store = store,
			session = session,
			economy = economy,
			inventory = inventory,
			modifiers = modifiers,
			upgrades = upgrades,
			zones = zones,
			collecting = collecting,
			selling = selling,
			monetization = monetization,
			analytics = analytics,
			gateway = gateway,
			prestige = prestige,
		},
	}
	return composed
end

return GameServer
