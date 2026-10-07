--!strict
-- Welt-Konvention im Workspace:
--   Workspace.FactoryWorld.Zones.<zoneId>   je ein Part pro Zone; Items erscheinen auf seiner Oberseite
--                                           (lokale +Y-Seite, Drehung des Parts wird beruecksichtigt)
--   Workspace.FactoryWorld.SellAreas.*      ein oder mehrere Parts; sie sind Volumen (z. B. unsichtbar,
--                                           CanCollide aus): Verkauft wird, wenn die Charakterposition darin liegt
-- validateWorld(config) liefert die Namen fehlender Teile; der Start bricht dann ab.
local Log = require(script.Parent.Parent.Parent.shared.Log)

export type WorldAdapter = {
	validateWorld: (self: WorldAdapter, config: any) -> { string },
	spawnPosition: (self: WorldAdapter, zoneId: string, rng: Random) -> Vector3,
	isInSellArea: (self: WorldAdapter, position: Vector3) -> boolean,
}

local ROOT_NAME = "FactoryWorld"
local ZONES_NAME = "Zones"
local SELL_AREAS_NAME = "SellAreas"

local WorldAdapter = {}

WorldAdapter.ROOT_NAME = ROOT_NAME

local function inside(part: BasePart, position: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(position)
	local half = part.Size / 2
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

function WorldAdapter.new(parent: Instance?, log: Log.Log?): WorldAdapter
	local container: Instance = parent or workspace
	local warnLog = log or Log.new()

	local function child(instance: Instance?, name: string): Instance?
		return if instance ~= nil then instance:FindFirstChild(name) else nil
	end

	local function zonePart(zoneId: string): BasePart?
		local part = child(child(child(container, ROOT_NAME), ZONES_NAME), zoneId)
		return if part ~= nil and part:IsA("BasePart") then part else nil
	end

	local world: WorldAdapter = {
		validateWorld = function(_self, config: any): { string }
			local missing: { string } = {}
			local root = child(container, ROOT_NAME)
			if root == nil then
				return { ROOT_NAME }
			end
			local zoneIds = {}
			for zoneId in config.zones do
				table.insert(zoneIds, zoneId)
			end
			table.sort(zoneIds)
			for _, zoneId in zoneIds do
				if zonePart(zoneId) == nil then
					table.insert(missing, string.format("%s.%s.%s", ROOT_NAME, ZONES_NAME, zoneId))
				end
			end
			local sellAreas = child(root, SELL_AREAS_NAME)
			local hasSellPart = false
			for _, part in if sellAreas ~= nil then sellAreas:GetChildren() else {} do
				if part:IsA("BasePart") then
					hasSellPart = true
				end
			end
			if not hasSellPart then
				table.insert(missing, string.format("%s.%s (at least one part)", ROOT_NAME, SELL_AREAS_NAME))
			end
			return missing
		end,

		spawnPosition = function(_self, zoneId: string, rng: Random): Vector3
			local part = zonePart(zoneId)
			if part == nil then
				warnLog:warnThrottled("zone:" .. zoneId, "[WorldAdapter] zone part missing: " .. zoneId)
				return Vector3.new(0, 0, 0)
			end
			local size = part.Size
			local localPoint =
				Vector3.new(rng:NextNumber(-0.5, 0.5) * size.X, size.Y / 2, rng:NextNumber(-0.5, 0.5) * size.Z)
			return part.CFrame:PointToWorldSpace(localPoint)
		end,

		isInSellArea = function(_self, position: Vector3): boolean
			local sellAreas = child(child(container, ROOT_NAME), SELL_AREAS_NAME)
			if sellAreas == nil then
				return false
			end
			for _, part in sellAreas:GetChildren() do
				if part:IsA("BasePart") and inside(part, position) then
					return true
				end
			end
			return false
		end,
	}
	return world
end

return WorldAdapter
