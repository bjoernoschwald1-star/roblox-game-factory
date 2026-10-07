--!strict
-- Test 45: der ganze Loop mit echter Verdrahtung ueber ProfileStore + PlayerSession + MemoryAdapter:
-- einsammeln -> verkaufen -> Reichweite upgraden -> mehr in Reichweite -> Zone 2 kaufen -> dort einsammeln
-- -> autosaveAll -> Freigabe -> auf zweitem Server neu laden.
local FactoryCore = game:GetService("ServerScriptService").FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local MemoryAdapter = require(FactoryCore.testing.MemoryAdapter)
local ProfileStore = require(FactoryCore.server.ProfileStore)
local PlayerSession = require(FactoryCore.server.PlayerSession)
local Economy = require(FactoryCore.server.Economy)
local Inventory = require(FactoryCore.server.Inventory)
local Modifiers = require(FactoryCore.server.Modifiers)
local Upgrades = require(FactoryCore.server.Upgrades)
local Zones = require(FactoryCore.server.Zones)
local Selling = require(FactoryCore.server.Selling)
local Collecting = require(FactoryCore.server.Collecting)
local Radius = require(FactoryCore.server.CollectTypes.Radius)

local CTX = { userId = 101 }
local ORIGIN = Vector3.new(0, 0, 0)
local FAR = Vector3.new(1000, 0, 1000)

local function newStore(memory: MemoryAdapter.MemoryAdapter, serverId: string): ProfileStore.ProfileStore
	return ProfileStore.new({
		storage = memory,
		keyPrefix = "profile_",
		defaults = function()
			return { coins = 0, inventory = {}, upgrades = {}, zones = {} }
		end,
		schemaVersion = 1,
		serverId = serverId,
		clock = function()
			return 1000
		end,
		sleep = function() end,
	})
end

return function(t: Runner.Api, _ctx: Runner.Context)
	t.describe("loop", function()
		t.it("45 collect -> sell -> upgrade range -> unlock zone 2 -> collect there -> save and reload", function()
			local memory = MemoryAdapter.new()
			local session = PlayerSession.new({
				store = newStore(memory, "server-a"),
				onLoadFailed = function() end,
			})
			t.expect(session:join(CTX).state).toBe("NEW")
			local function getProfile(ctx)
				return session:get(ctx)
			end

			local modifiers = Modifiers.new({ base = { range = 5, capacity = 10, sellFactor = 1 } })
			local economy = Economy.new({ getProfile = getProfile })
			local upgrades = Upgrades.new({
				getProfile = getProfile,
				economy = economy,
				dimensions = { range_boost = { stat = "range", levels = { { cost = 10, add = 10 } } } },
			})
			modifiers:registerSource("upgrades", upgrades:modifierSource())
			local zones = Zones.new({
				getProfile = getProfile,
				economy = economy,
				upgrades = upgrades,
				zones = {
					zone_a = { order = 1, condition = { type = "always" } },
					zone_b = { order = 2, condition = { type = "purchase", cost = 20 } },
				},
			})
			t.expect(zones:validate()).toBe(true)
			local inventory = Inventory.new({
				getProfile = getProfile,
				getCapacity = function(ctx)
					return math.floor(modifiers:value(ctx, "capacity"))
				end,
			})
			local positions: { [string]: { Vector3 } } = {
				zone_a = { Vector3.new(3, 0, 0), Vector3.new(10, 0, 0), Vector3.new(14, 0, 0) },
				zone_b = { Vector3.new(5, 0, 0), Vector3.new(6, 0, 0) },
			}
			local collecting = Collecting.new({
				items = {
					item_a = { zoneId = "zone_a", spawnWeight = 1 },
					item_b = { zoneId = "zone_b", spawnWeight = 1 },
				},
				zones = {
					zone_a = { density = 3, respawnSeconds = 0 },
					zone_b = { density = 2, respawnSeconds = 0 },
				},
				inventory = inventory,
				isZoneUnlocked = function(ctx, zoneId)
					return zones:isUnlocked(ctx, zoneId)
				end,
				getRange = function(ctx)
					return modifiers:value(ctx, "range")
				end,
				spawnPosition = function(zoneId: string): Vector3
					local queue = positions[zoneId]
					return if #queue > 0 then table.remove(queue, 1) :: Vector3 else FAR
				end,
				collectType = Radius,
				collectParams = {},
				rangeTolerance = 2,
				rateLimit = { maxItems = 100, windowSeconds = 10 },
				clock = function()
					return 0
				end,
				rng = Random.new(3),
			})
			local selling = Selling.new({
				inventory = inventory,
				economy = economy,
				modifiers = modifiers,
				prices = { item_a = 10, item_b = 25 },
				canSell = function()
					return true
				end,
			})

			-- Startzone: nur das Item bei 3 Studs liegt in Reichweite 5 + 2.
			collecting:startPlayer(CTX)
			t.expect(#collecting:collect(CTX, ORIGIN).collected).toBe(1)
			t.expect(selling:sell(CTX).earned).toBe(10)

			-- Reichweite upgraden (5 -> 15): die Items bei 10 und 14 Studs kommen in Reichweite.
			t.expect(upgrades:purchase(CTX, "range_boost")).toBe(true)
			t.expect(modifiers:value(CTX, "range")).toBe(15)
			t.expect(#collecting:collect(CTX, ORIGIN).collected).toBe(2)
			t.expect(selling:sell(CTX).earned).toBe(20)

			-- Zone 2 kaufen und dort einsammeln.
			t.expect(collecting:instances(CTX)).toEqual({})
			t.expect(zones:tryUnlock(CTX, "zone_b")).toBe(true)
			t.expect(economy:balance(CTX)).toBe(0)
			collecting:refill(CTX)
			local inZoneB = collecting:collect(CTX, ORIGIN)
			t.expect(#inZoneB.collected).toBe(2)
			for _, instance in inZoneB.collected do
				t.expect(instance.zoneId).toBe("zone_b")
			end
			t.expect(selling:sell(CTX).earned).toBe(50)
			t.expect(economy:balance(CTX)).toBe(50)

			-- Speichern, freigeben, auf zweitem Server neu laden.
			t.expect(session:autosaveAll()).toEqual({ saved = 1, failed = {} })
			t.expect(session:leave(CTX)).toBe(true)
			local reloaded = newStore(memory, "server-b"):load(CTX)
			t.expect(reloaded.state).toBe("LOADED")
			local profile = reloaded.profile :: ProfileStore.Profile
			t.expect(profile.coins).toBe(50)
			t.expect(profile.upgrades).toEqual({ range_boost = 1 })
			t.expect(profile.zones).toEqual({ zone_b = true })
			t.expect(profile.inventory).toEqual({})
		end)
	end)
end
