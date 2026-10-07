--!strict
-- Reine Logik des Onboardings (Erweiterungspunkt: Schritte aus Daten). Ein Schritt ist
-- { id, textKey, target = "item" | "sell" | "none", condition = "inventory" | "coins_increased" |
--   "any_upgrade" | "second_zone" }. Ohne Daten des Games gilt DEFAULT_STEPS: collect -> sell -> upgrade ->
-- unlockZone. update(snapshot) prueft den aktuellen Schritt (auch mehrere nacheinander) und liefert den
-- aktuellen Schritt oder nil, wenn das Onboarding fertig ist.
-- Abschlussbedingungen: inventory = Inventar > 0; coins_increased = Coins hoeher als beim Start des Schritts;
-- any_upgrade = irgendeine Upgrade-Stufe > 0; second_zone = Zone mit der zweitkleinsten order frei.
-- Erster Schnappschuss: Schritte, deren Zustand bereits erreicht ist (any_upgrade, second_zone), werden samt
-- allen davor liegenden Schritten uebersprungen - ein zurueckkehrender Spieler beginnt nicht wieder von vorn.
-- FULL_HINT ist ein Anzeige-Schritt fuer das volle Inventar (Hinweis + Strahl zur Verkaufsflaeche); er gehoert
-- nicht zur Schrittfolge, der Client zeigt ihn statt des aktuellen Schritts, solange das Inventar voll ist.

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

-- Bedingungen, die einen dauerhaften Zustand beschreiben (nicht ein Ereignis seit Schrittbeginn).
local STATE_CONDITIONS: { [string]: boolean } = { any_upgrade = true, second_zone = true }

local FULL_HINT: Step = { id = "full", textKey = "hint_full", target = "sell", condition = "none" }

local OnboardingModel = {}

OnboardingModel.DEFAULT_STEPS = DEFAULT_STEPS
OnboardingModel.FULL_HINT = FULL_HINT

-- Angezeigter Schritt: waehrend eines Wow-Banners (gleicher Platz) keiner, bei vollem Inventar FULL_HINT,
-- sonst der aktuelle Schritt.
function OnboardingModel.displayStep(bannerShown: boolean, full: boolean, current: Step?): Step?
	if bannerShown then
		return nil
	end
	return if full then FULL_HINT else current
end

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
	local seenFirst = false

	local model: OnboardingModel = {
		update = function(_self, snapshot: any): Step?
			if not seenFirst then
				seenFirst = true
				-- Letzten bereits erfuellten Zustands-Schritt suchen; alles bis dahin gilt als erledigt.
				for position = #list, 1, -1 do
					local step = list[position]
					if STATE_CONDITIONS[step.condition] and met(step.condition, snapshot, nil) then
						index = position + 1
						break
					end
				end
			end
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
