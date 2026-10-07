--!strict
-- Client-Seite des Rueckwegs: nimmt Schnappschuesse des Servers an (nur zur Anzeige). Eigenstaendig, ohne
-- require auf Server-Module. Schnappschuesse mit seq <= der letzten angenommenen seq und strukturell ungueltige
-- Schnappschuesse werden ohne Fehler verworfen. get() liefert eine Kopie; onChanged-Callbacks laufen in pcall.

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

export type ClientState = {
	apply: (self: ClientState, snapshot: any) -> boolean,
	get: (self: ClientState) -> Snapshot?,
	onChanged: (self: ClientState, callback: (snapshot: Snapshot) -> ()) -> () -> (),
	canAfford: (self: ClientState, dimension: string) -> boolean,
	isFull: (self: ClientState) -> boolean,
	nextZone: (self: ClientState) -> string?,
}

local function isFinite(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function copy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in value :: any do
		result[copy(key)] = copy(item)
	end
	return (result :: any) :: T
end

-- Strukturpruefung eines empfangenen Schnappschusses.
local function isValid(snapshot: any): boolean
	if type(snapshot) ~= "table" then
		return false
	end
	for _, key in { "seq", "coins", "capacity", "inventoryCount", "range", "sellFactor" } do
		if not isFinite(snapshot[key]) then
			return false
		end
	end
	if type(snapshot.inventory) ~= "table" or type(snapshot.upgrades) ~= "table" then
		return false
	end
	if type(snapshot.zones) ~= "table" or type(snapshot.items) ~= "table" then
		return false
	end
	for itemTypeId, count in snapshot.inventory do
		if type(itemTypeId) ~= "string" or not isFinite(count) then
			return false
		end
	end
	for dimension, upgrade in snapshot.upgrades do
		if type(dimension) ~= "string" or type(upgrade) ~= "table" then
			return false
		end
		if not isFinite(upgrade.level) or not isFinite(upgrade.maxLevel) then
			return false
		end
		if upgrade.nextCost ~= nil and not isFinite(upgrade.nextCost) then
			return false
		end
	end
	for zoneId, zone in snapshot.zones do
		if type(zoneId) ~= "string" or type(zone) ~= "table" then
			return false
		end
		if type(zone.unlocked) ~= "boolean" or not isFinite(zone.order) then
			return false
		end
	end
	for _, item in snapshot.items do
		if type(item) ~= "table" or typeof(item.position) ~= "Vector3" then
			return false
		end
		if type(item.instanceId) ~= "string" or type(item.itemTypeId) ~= "string" or type(item.zoneId) ~= "string" then
			return false
		end
	end
	return true
end

local ClientState = {}

ClientState.isValid = isValid

function ClientState.new(): ClientState
	local current: Snapshot? = nil
	local listeners: { (snapshot: Snapshot) -> () } = {}

	local state: ClientState = {
		apply = function(_self, snapshot: any): boolean
			if not isValid(snapshot) then
				return false
			end
			if current ~= nil and snapshot.seq <= current.seq then
				return false
			end
			current = copy(snapshot) :: Snapshot
			for _, listener in table.clone(listeners) do
				local ok, err = pcall(listener, copy(current) :: Snapshot)
				if not ok then
					warn("[ClientState] onChanged callback failed: " .. tostring(err))
				end
			end
			return true
		end,

		get = function(_self): Snapshot?
			return if current ~= nil then copy(current) else nil
		end,

		onChanged = function(_self, callback: (snapshot: Snapshot) -> ()): () -> ()
			table.insert(listeners, callback)
			return function()
				local index = table.find(listeners, callback)
				if index ~= nil then
					table.remove(listeners, index)
				end
			end
		end,

		canAfford = function(_self, dimension: string): boolean
			if current == nil then
				return false
			end
			local upgrade = current.upgrades[dimension]
			return upgrade ~= nil and upgrade.nextCost ~= nil and current.coins >= upgrade.nextCost
		end,

		isFull = function(_self): boolean
			return current ~= nil and current.inventoryCount >= current.capacity
		end,

		nextZone = function(_self): string?
			if current == nil then
				return nil
			end
			local best: string? = nil
			local bestOrder = math.huge
			for zoneId, zone in current.zones do
				if not zone.unlocked and zone.order < bestOrder then
					best, bestOrder = zoneId, zone.order
				end
			end
			return best
		end,
	}
	return state
end

return ClientState
