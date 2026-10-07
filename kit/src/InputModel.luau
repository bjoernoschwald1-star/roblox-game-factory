--!strict
-- Reine Logik der Eingabe: bildet Tasten und Gamepad-Knoepfe (Enum.KeyCode-Namen) auf Absichten ab; Touch
-- laeuft ueber die HUD-Buttons auf dieselben Absichten.
--   Tastatur: E = einsammeln, Q = verkaufen. Gamepad: ButtonX = einsammeln, ButtonY = verkaufen.
-- Auto-Einsammeln (nur Komfort, der Server prueft ohnehin): tick(snapshot, position) sendet hoechstens alle
-- autoIntervalSeconds ein collect, wenn mindestens ein eigenes Item innerhalb der Reichweite (range aus dem
-- Schnappschuss) um die Charakterposition liegt und das Inventar nicht voll ist (inventoryCount < capacity);
-- volle Inventare wuerde der Server ohnehin ablehnen, das spart Remote-Last.

export type Intents = {
	collect: (self: any) -> boolean,
	sell: (self: any) -> boolean,
}

export type Options = {
	intents: Intents,
	clock: (() -> number)?,
	autoIntervalSeconds: number?,
	bindings: { [string]: string }?,
}

export type InputModel = {
	onInput: (self: InputModel, keyCodeName: string) -> string?,
	tick: (self: InputModel, snapshot: any, position: Vector3?) -> boolean,
}

local DEFAULT_BINDINGS: { [string]: string } = {
	E = "collect",
	Q = "sell",
	ButtonX = "collect",
	ButtonY = "sell",
}

local InputModel = {}

InputModel.DEFAULT_BINDINGS = DEFAULT_BINDINGS

function InputModel.new(options: Options): InputModel
	local intents = options.intents
	local clock: () -> number = options.clock or os.clock
	local interval = options.autoIntervalSeconds or 0.25
	local bindings = options.bindings or DEFAULT_BINDINGS
	local lastAuto: number? = nil

	local model: InputModel = {
		-- Liefert die ausgeloeste Absicht oder nil, wenn die Taste nicht belegt ist.
		onInput = function(_self, keyCodeName: string): string?
			local action = bindings[keyCodeName]
			if action == "collect" then
				intents:collect()
			elseif action == "sell" then
				intents:sell()
			else
				return nil
			end
			return action
		end,

		tick = function(_self, snapshot: any, position: Vector3?): boolean
			if snapshot == nil or position == nil then
				return false
			end
			if
				type(snapshot.inventoryCount) == "number"
				and type(snapshot.capacity) == "number"
				and snapshot.inventoryCount >= snapshot.capacity
			then
				return false
			end
			local now = clock()
			if lastAuto ~= nil and now - lastAuto < interval then
				return false
			end
			for _, item in snapshot.items do
				if (item.position - position).Magnitude <= snapshot.range then
					lastAuto = now
					intents:collect()
					return true
				end
			end
			return false
		end,
	}
	return model
end

return InputModel
