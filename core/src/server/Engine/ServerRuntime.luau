--!strict
-- Bruecke zwischen GameServer.compose und dem echten Roblox-Server. Jede Roblox-Abhaengigkeit steckt in einem
-- austauschbaren Adapter (Players, Character, Remotes, World, Market, Analytics, Scheduler, Lifecycle); Tests
-- ersetzen sie durch Fakes. Es gibt kein Skript, das start automatisch aufruft.
--
-- start: Config validieren, Welt pruefen (validateWorld), sell.trigger muss "zone" sein (npc/button sind in
-- Phase 0 nicht umgesetzt), dann compose mit Diensten aus den Adaptern. Spieler (auch bereits vorhandene) werden
-- angemeldet, die vier Remotes laufen ausschliesslich ueber game:dispatch, Kaeufe ueber ProcessReceipt,
-- Pass-Kaeufe wirken erst nach serverseitiger Besitzpruefung, refillAll/autosaveAll laufen im Scheduler.
-- Zustand zum Client: GameServer.flushState im Takt stateSeconds, Versand ueber RemoteBinder.fireClient an das
-- Remote "stateUpdate" (nur an den jeweiligen Spieler).
-- Shutdown (BindToClose, Roblox wartet hoechstens 30 s): alle Spieler werden parallel abgemeldet und freigegeben;
-- nach shutdownBudgetSeconds werden nicht freigegebene Spieler per warn gemeldet.
local AnalyticsAdapter = require(script.Parent.AnalyticsAdapter)
local CharacterAdapter = require(script.Parent.CharacterAdapter)
local GameServer = require(script.Parent.Parent.GameServer)
local Log = require(script.Parent.Parent.Parent.shared.Log)
local MarketAdapter = require(script.Parent.MarketAdapter)
local PlayersAdapter = require(script.Parent.PlayersAdapter)
local RemoteBinder = require(script.Parent.RemoteBinder)
local RobloxDataStoreAdapter = require(script.Parent.Parent.Storage.RobloxDataStoreAdapter)
local Scheduler = require(script.Parent.Scheduler)
local Schema = require(script.Parent.Parent.Config.Schema)
local StorageAdapter = require(script.Parent.Parent.Storage.StorageAdapter)
local Validator = require(script.Parent.Parent.Config.Validator)
local WorldAdapter = require(script.Parent.WorldAdapter)

export type Lifecycle = {
	bindToClose: (self: Lifecycle, handler: () -> ()) -> (),
}

export type Adapters = {
	players: PlayersAdapter.PlayersAdapter?,
	character: CharacterAdapter.CharacterAdapter?,
	remotes: RemoteBinder.RemoteBinder?,
	world: WorldAdapter.WorldAdapter?,
	market: MarketAdapter.MarketAdapter?,
	analytics: AnalyticsAdapter.AnalyticsAdapter?,
	scheduler: Scheduler.Scheduler?,
	lifecycle: Lifecycle?,
}

export type Options = {
	adapters: Adapters?,
	storage: StorageAdapter.StorageAdapter?,
	dataStoreName: string?,
	keyPrefix: string?,
	serverId: string?,
	autosaveSeconds: number?,
	refillSeconds: number?,
	shutdownBudgetSeconds: number?,
	loadFailedMessage: string?,
	stateSeconds: number?, -- Takt fuer flushState (Standard 0.2)
	clock: (() -> number)?,
	sleep: ((seconds: number) -> ())?,
	rng: Random?,
	log: Log.Log?,
}

export type Runtime = {
	game: GameServer.Game,
	stop: (self: Runtime) -> (),
	shutdown: (self: Runtime) -> { number },
}

local DEFAULT_KEY_PREFIX = "player_"
local DEFAULT_LOAD_FAILED = "Your progress could not be loaded right now. Please rejoin in a moment."

local ServerRuntime = {}

local function defaultServerId(): string
	local jobId = game.JobId
	if type(jobId) == "string" and jobId ~= "" then
		return jobId
	end
	-- JobId ist in Studio leer.
	return "local-" .. game:GetService("HttpService"):GenerateGUID(false)
end

function ServerRuntime.start(config: Schema.GameConfig, options: Options): Runtime
	local validation = Validator.validate(config)
	if not validation.ok then
		error("ServerRuntime: invalid config\n" .. Validator.format(validation), 0)
	end
	if config.sell.trigger ~= "zone" then
		error(
			string.format(
				"ServerRuntime: sell.trigger %q is not implemented in Phase 0 (only %q)",
				config.sell.trigger,
				"zone"
			),
			0
		)
	end

	local adapters: Adapters = options.adapters or {}
	local log = options.log or Log.new({ clock = options.clock })
	local world = adapters.world or WorldAdapter.new(nil, log)
	local missing = world:validateWorld(config)
	if #missing > 0 then
		error("ServerRuntime: world is missing " .. table.concat(missing, ", "), 0)
	end

	local storage = options.storage
	if storage == nil then
		assert(
			type(options.dataStoreName) == "string" and options.dataStoreName ~= "",
			"ServerRuntime: dataStoreName is required"
		)
		storage = RobloxDataStoreAdapter.new(options.dataStoreName :: string)
	end

	local playersAdapter = adapters.players or PlayersAdapter.new()
	local character = adapters.character or CharacterAdapter.new()
	local remotes = adapters.remotes or RemoteBinder.new()
	local market = adapters.market or MarketAdapter.new()
	local scheduler = adapters.scheduler or Scheduler.new(log)
	local lifecycle: Lifecycle = adapters.lifecycle
		or {
			bindToClose = function(_self, handler: () -> ())
				game:BindToClose(handler)
			end,
		}
	local loadFailedMessage = options.loadFailedMessage
		or (if type(config.texts.system_load_failed) == "string" then config.texts.system_load_failed else nil)
		or DEFAULT_LOAD_FAILED

	-- Aktive Spieler-Objekte pro userId (fuer Position, Kick und Analytics).
	local players: { [number]: any } = {}
	local function findPlayer(userId: number): any
		return players[userId]
	end
	local analyticsAdapter = adapters.analytics or AnalyticsAdapter.new({ findPlayer = findPlayer })

	local function positionOf(ctx): Vector3?
		local player = players[ctx.userId]
		return if player ~= nil then character:position(player) else nil
	end

	local composed = GameServer.compose(config, {
		storage = storage :: StorageAdapter.StorageAdapter,
		dataStoreKeyPrefix = options.keyPrefix or DEFAULT_KEY_PREFIX,
		serverId = options.serverId or defaultServerId(),
		clock = options.clock or function()
			return DateTime.now().UnixTimestampMillis / 1000
		end,
		sleep = options.sleep,
		rng = options.rng or Random.new(),
		spawnPosition = function(zoneId: string, rng: Random): Vector3
			return world:spawnPosition(zoneId, rng)
		end,
		getPosition = positionOf,
		canSell = function(ctx): boolean
			local position = positionOf(ctx)
			return position ~= nil and world:isInSellArea(position)
		end,
		ownsPass = function(userId: number, passId: number): boolean
			return market:ownsPass(userId, passId)
		end,
		analyticsSink = analyticsAdapter.sink,
		onLoadFailed = function(ctx)
			local player = players[ctx.userId]
			if player ~= nil then
				playersAdapter:kick(player, loadFailedMessage)
			end
		end,
		log = log,
		-- Zustand zum Client ueber das Remote "stateUpdate"; Spieler nicht mehr da -> verwerfen. Ein Binder ohne
		-- fireClient (z. B. ein aelterer Test-Fake) schaltet den Rueckweg ab.
		sendState = if remotes.fireClient ~= nil
			then function(ctx, snapshot)
				local player = players[ctx.userId]
				if player ~= nil then
					remotes:fireClient(RemoteBinder.STATE_REMOTE, player, snapshot)
				end
			end
			else nil,
	})

	local productRoles: { [number]: string } = {}
	for role, product in config.products do
		productRoles[product.productId] = role
	end
	local passRoles: { [number]: string } = {}
	for role, pass in config.passes do
		passRoles[pass.passId] = role
	end

	local connections: { PlayersAdapter.Connection } = {}
	local stops: { () -> () } = {}
	local joining: { [number]: boolean } = {}

	local function onAdded(player: any)
		local userId = player.UserId
		if players[userId] ~= nil or joining[userId] then
			return
		end
		joining[userId] = true
		players[userId] = player
		local result = composed:playerJoined({ userId = userId }, playersAdapter:joinSource(player))
		joining[userId] = nil
		if result.profile == nil then
			-- Laden fehlgeschlagen: onLoadFailed hat bereits gekickt; kein Spiel mit leerem Profil.
			players[userId] = nil
		end
	end

	local function onRemoving(player: any)
		local userId = player.UserId
		if players[userId] == nil then
			return
		end
		composed:playerLeaving({ userId = userId })
		players[userId] = nil
	end

	table.insert(connections, playersAdapter:onAdded(onAdded))
	table.insert(connections, playersAdapter:onRemoving(onRemoving))
	for _, player in playersAdapter:getPlayers() do
		task.spawn(onAdded, player)
	end

	for _, name in Schema.REMOTES do
		table.insert(
			connections,
			remotes:bind(name, function(player: any, ...: any)
				-- Rueckgaben gehen nie an den Client.
				composed:dispatch({ userId = player.UserId }, name, ...)
			end)
		)
	end

	market:setReceiptHandler(function(receipt: any): MarketAdapter.Decision
		return composed:processReceipt(receipt)
	end)
	table.insert(
		connections,
		market:onPassPromptFinished(function(player: any, passId: number, wasPurchased: boolean)
			local role = passRoles[passId]
			if not wasPurchased or role == nil then
				return
			end
			-- Wirksam erst nach serverseitiger Besitzpruefung.
			local ok, owned = pcall(function()
				return market:ownsPass(player.UserId, passId)
			end)
			if ok and owned == true then
				composed:setPassOwned({ userId = player.UserId }, role, true)
			elseif not ok then
				log:warnThrottled("ownsPass", "[ServerRuntime] ownsPass failed: " .. tostring(owned))
			end
		end)
	)
	table.insert(
		connections,
		market:onProductPromptFinished(function(userId: number, productId: number, wasPurchased: boolean)
			local role = productRoles[productId]
			if role == nil or players[userId] == nil then
				return
			end
			composed.modules.analytics:track({ userId = userId }, "purchase_attempt", {
				role = role,
				accepted = wasPurchased == true,
			})
		end)
	)

	table.insert(
		stops,
		scheduler:every(options.refillSeconds or 1, function()
			composed:refillAll()
		end)
	)
	table.insert(
		stops,
		scheduler:every(options.stateSeconds or 0.2, function()
			composed:flushState()
		end)
	)
	table.insert(
		stops,
		scheduler:every(options.autosaveSeconds or 60, function()
			composed:autosaveAll()
		end)
	)

	local function stopLoops()
		for _, stopLoop in stops do
			stopLoop()
		end
		table.clear(stops)
	end

	-- Meldet alle Spieler parallel ab; liefert die userIds, die im Budget nicht freigegeben wurden.
	local function shutdown(): { number }
		stopLoops()
		local budget = options.shutdownBudgetSeconds or 25
		local pending: { [number]: boolean } = {}
		for userId in players do
			pending[userId] = true
		end
		for userId in pending do
			task.spawn(function()
				local ok, err = pcall(function()
					composed:playerLeaving({ userId = userId })
				end)
				if not ok then
					log:warnThrottled("shutdown", "[ServerRuntime] release failed: " .. tostring(err))
				else
					pending[userId] = nil
					players[userId] = nil
				end
			end)
		end
		local startedAt = os.clock()
		while next(pending) ~= nil and os.clock() - startedAt < budget do
			task.wait(0.05)
		end
		local unreleased: { number } = {}
		for userId in pending do
			table.insert(unreleased, userId)
		end
		table.sort(unreleased)
		if #unreleased > 0 then
			warn("[ServerRuntime] not released before shutdown: " .. table.concat(unreleased, ", "))
		end
		return unreleased
	end
	lifecycle:bindToClose(function()
		shutdown()
	end)

	local runtime: Runtime = {
		game = composed,
		stop = function(_self)
			stopLoops()
			for _, connection in connections do
				connection:Disconnect()
			end
			table.clear(connections)
			market:clearReceiptHandler()
		end,
		shutdown = function(_self): { number }
			return shutdown()
		end,
	}
	return runtime
end

return ServerRuntime
