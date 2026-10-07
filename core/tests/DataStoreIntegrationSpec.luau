--!strict
-- Test 13: ProfileStore mit echtem DataStore (RobloxDataStoreAdapter) im CI-Place.
-- Ausschliesslich DataStore "ci_core_profiles", Schluessel mit Lauf-ID; der Schluessel wird am Ende geloescht.
local ServerScriptService = game:GetService("ServerScriptService")
local FactoryCore = ServerScriptService.FactoryCore
local Runner = require(FactoryCore.testing.Runner)
local RobloxDataStoreAdapter = require(FactoryCore.server.Storage.RobloxDataStoreAdapter)
local ProfileStore = require(FactoryCore.server.ProfileStore)

local STORE_NAME = "ci_core_profiles"
local CTX = { userId = 1 }

return function(t: Runner.Api, ctx: Runner.Context)
	t.describe("profile store datastore", function()
		t.it("13 real DataStore: NEW -> save -> release -> LOADED again, key removed", function()
			local adapter = RobloxDataStoreAdapter.new(STORE_NAME)
			local keyPrefix = "run_" .. ctx.runId .. "_"
			local key = keyPrefix .. "1"

			local function newStore(serverId: string): ProfileStore.ProfileStore
				return ProfileStore.new({
					storage = adapter,
					keyPrefix = keyPrefix,
					defaults = function()
						return { points = 0 }
					end,
					schemaVersion = 1,
					lockTtlSeconds = 60,
					lockWait = { attempts = 0, delaySeconds = 0 },
					retry = { attempts = 3, baseDelaySeconds = 1 },
					serverId = serverId .. "_" .. ctx.runId,
				})
			end

			local scenarioOk, scenarioErr = pcall(function()
				local storeA = newStore("ci-a")
				local first = storeA:load(CTX)
				t.expect(first.state).toBe("NEW")
				local profile = first.profile :: ProfileStore.Profile
				profile.points = 11
				t.expect(storeA:save(CTX, profile)).toBe(true)
				t.expect(storeA:release(CTX, profile)).toBe(true)

				local storeB = newStore("ci-b")
				local second = storeB:load(CTX)
				t.expect(second.state).toBe("LOADED")
				local reloaded = second.profile :: ProfileStore.Profile
				t.expect(reloaded.points).toBe(11)
				t.expect(reloaded.session.serverId).toBe("ci-b_" .. ctx.runId)
				t.expect(storeB:release(CTX, reloaded)).toBe(true)
			end)

			-- Aufraeumen auch dann, wenn das Szenario fehlschlaegt.
			local removeOk, removeErr = adapter:remove(key)
			if not scenarioOk then
				error(scenarioErr, 0)
			end
			if not removeOk then
				error("cleanup failed: " .. tostring(removeErr), 0)
			end
			local readOk, leftover = adapter:read(key)
			t.expect(readOk).toBe(true)
			t.expect(leftover).toBe(nil)
		end)
	end)
end
