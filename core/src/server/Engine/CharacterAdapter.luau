--!strict
-- Liefert die Position eines Spielers vom Server (Wurzelteil des Charakters), nie vom Client.
-- Wurzelteil: Model.PrimaryPart des Charakters, sonst ein Kind "HumanoidRootPart".
-- Kein Charakter oder kein Wurzelteil -> nil.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/Player#Character
--       https://create.roblox.com/docs/reference/engine/classes/Model#PrimaryPart
export type CharacterAdapter = {
	position: (self: CharacterAdapter, player: any) -> Vector3?,
}

local CharacterAdapter = {}

function CharacterAdapter.new(): CharacterAdapter
	local adapter: CharacterAdapter = {
		position = function(_self, player: any): Vector3?
			local ok, position = pcall(function(): Vector3?
				local character = player.Character
				if character == nil then
					return nil
				end
				local root = character.PrimaryPart or character:FindFirstChild("HumanoidRootPart")
				if root == nil or not root:IsA("BasePart") then
					return nil
				end
				return root.Position
			end)
			return if ok then position else nil
		end,
	}
	return adapter
end

return CharacterAdapter
