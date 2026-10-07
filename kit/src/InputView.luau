--!strict
-- Bindet echte Eingaben an das InputModel: UserInputService.InputBegan (Tastatur, Gamepad; Eingaben, die
-- bereits von der UI verarbeitet wurden, werden ignoriert) und RunService.Heartbeat fuer das Auto-Einsammeln.
-- Nur im Client (LocalScript) sinnvoll.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/UserInputService#InputBegan
--       https://create.roblox.com/docs/reference/engine/classes/RunService#Heartbeat
local InputModel = require(script.Parent.InputModel)

export type InputView = {
	destroy: (self: InputView) -> (),
}

local InputView = {}

function InputView.new(model: InputModel.InputModel, getSnapshot: () -> any, getPosition: () -> Vector3?): InputView
	local UserInputService = game:GetService("UserInputService")
	local RunService = game:GetService("RunService")
	local connections = {
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if gameProcessed then
				return
			end
			model:onInput(input.KeyCode.Name)
		end),
		RunService.Heartbeat:Connect(function()
			model:tick(getSnapshot(), getPosition())
		end),
	}
	local view: InputView = {
		destroy = function(_self)
			for _, connection in connections do
				connection:Disconnect()
			end
		end,
	}
	return view
end

return InputView
