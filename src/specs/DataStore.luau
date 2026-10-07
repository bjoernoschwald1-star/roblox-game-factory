--!strict
-- Schreibt run_<Lauf-ID> in den DataStore "ci_spike", liest zurueck und loescht wieder.
-- Ausschliesslich dieser Namensraum wird angefasst.
local DataStoreService = game:GetService("DataStoreService")
local Runner = require(script.Parent.Parent.Runner)

local STORE_NAME = "ci_spike"

return function(t: Runner.Api, ctx: Runner.Context)
	t.describe("datastore", function()
		t.it("writes, reads back and removes the run key", function()
			local store = DataStoreService:GetDataStore(STORE_NAME)
			local key = "run_" .. ctx.runId
			local value = { runId = ctx.runId, answer = 42 }

			store:SetAsync(key, value)
			local readOk, readBack = pcall(function()
				return store:GetAsync(key)
			end)
			-- Aufraeumen auch dann, wenn das Lesen fehlschlaegt.
			local removed = store:RemoveAsync(key)

			if not readOk then
				error(readBack, 0)
			end
			t.expect(readBack).toEqual(value)
			t.expect(removed).toEqual(value)
		end)
	end)
end
