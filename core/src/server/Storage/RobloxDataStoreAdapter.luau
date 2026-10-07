--!strict
-- StorageAdapter auf Basis eines Roblox-DataStores. Jeder Aufruf laeuft in pcall; Schreiben nur per UpdateAsync.
local StorageAdapter = require(script.Parent.StorageAdapter)

local RobloxDataStoreAdapter = {}

function RobloxDataStoreAdapter.new(name: string, dataStoreService: DataStoreService?): StorageAdapter.StorageAdapter
	local service = dataStoreService or game:GetService("DataStoreService")
	local store = service:GetDataStore(name)

	local adapter: StorageAdapter.StorageAdapter = {
		read = function(_self, key: string): (boolean, any)
			local ok, value = pcall(function()
				return store:GetAsync(key)
			end)
			return ok, value
		end,

		update = function(_self, key: string, transform: (old: any) -> any): (boolean, any)
			local ok, value = pcall(function()
				return store:UpdateAsync(key, function(old: any)
					return transform(old)
				end)
			end)
			return ok, value
		end,

		remove = function(_self, key: string): (boolean, any)
			local ok, value = pcall(function()
				return store:RemoveAsync(key)
			end)
			return ok, value
		end,
	}
	return adapter
end

return RobloxDataStoreAdapter
