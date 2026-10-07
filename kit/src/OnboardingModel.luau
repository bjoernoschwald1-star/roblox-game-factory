--!strict
-- Reine Logik des Onboardings (Erweiterungspunkt: Schritte aus Daten). Ein Schritt ist
-- { id, textKey, target = "item" | "sell" | "none", condition = "inventory" | "coins_increased" |
--   "any_upgrade" | "second_zone" }. Ohne Daten des Games gilt DEFAULT_STEPS: collect -> sell -> upgrade ->
-- unlockZone. update(snapshot) prueft den aktuellen Schritt (auch mehrere nacheinander) und liefert den
-- aktuellen Schritt oder nil, wenn das Onboarding fertig ist.
-- Abschlussbedingungen: inventory = Inventar > 0; coins_increased = Coins hoeher als beim Start des Schritts;
-- any_upgrade = irgendeine Upgrade-Stufe > 0; second_zone = Zone mit der zweitkleinsten order frei.

export type Step = {
	id: string,
	textKey: string,
	target: string,
	condition: string,
}

export type OnboardingModel = {
	update: (self: OnboardingModel, snapshot: any) -> Step?,
	current: (self: OnboardingModel) -> Step?,
	isDone: (self: OnboardingModel) -> boolean,
}

local DEFAULT_STEPS: { Step } = {
	{ id = "collect", textKey = "onboarding_collect", target = "item", condition = "inventory" },
	{ id = "sell", textKey = "onboarding_sell", target = "sell", condition = "coins_increased" },
	{ id = "upgrade", textKey = "onboarding_upgrade", target = "none", condition = "any_upgrade" },
	{ id = "unlockZone", textKey = "onboarding_unlock", target = "none", condition = "second_zone" },
}

local OnboardingModel = {}

OnboardingModel.DEFAULT_STEPS = DEFAULT_STEPS

local function secondZoneUnlocked(snapshot: any): boolean
	local zones = {}
	for _, zone in snapshot.zones do
		table.insert(zones, zone)
	end
	table.sort(zones, function(a, b)
		return a.order < b.order
	end)
	return zones[2] ~= nil and zones[2].unlocked == true
end

local function met(condition: string, snapshot: any, startCoins: number?): boolean
	if condition == "inventory" then
		return snapshot.inventoryCount > 0
	elseif condition == "coins_increased" then
		return startCoins ~= nil and snapshot.coins > startCoins
	elseif condition == "any_upgrade" then
		for _, upgrade in snapshot.upgrades do
			if upgrade.level > 0 then
				return true
			end
		end
		return false
	elseif condition == "second_zone" then
		return secondZoneUnlocked(snapshot)
	end
	return false
end

function OnboardingModel.new(steps: { Step }?): OnboardingModel
	local list = steps or DEFAULT_STEPS
	local index = 1
	local startCoins: number? = nil

	local model: OnboardingModel = {
		update = function(_self, snapshot: any): Step?
			while list[index] ~= nil do
				if startCoins == nil then
					startCoins = snapshot.coins
				end
				if not met(list[index].condition, snapshot, startCoins) then
					break
				end
				index += 1
				startCoins = snapshot.coins
			end
			return list[index]
		end,
		current = function(_self): Step?
			return list[index]
		end,
		isDone = function(_self): boolean
			return list[index] == nil
		end,
	}
	return model
end

return OnboardingModel
