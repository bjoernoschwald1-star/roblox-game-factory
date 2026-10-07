--!strict
-- Sink fuer das Analytics-Modul: bildet die festen Events auf AnalyticsService ab.
-- - Jedes Event -> LogCustomEvent(player, eventName, value, customFields). value = durationSeconds bei
--   session_end, zoneIndex bei zone_unlock, sonst 1 (Zaehler).
-- - Events mit funnelStep (session_start 1 nur bei der ersten Sitzung, first_collect 2, first_sell 3,
--   first_upgrade 4, zone_unlock(2) 5) zuerst -> LogOnboardingFunnelStepEvent(player, step, eventName,
--   customFields): der Funnel ist ein einmaliger Onboarding-Funnel (Schritte 1-100, Name nur zur Anzeige).
-- - customFields nutzt nur die drei dokumentierten Schluessel aus Enum.AnalyticsCustomFieldKeys:
--   CustomField01 = configVersion, CustomField02 = source bzw. role, CustomField03 = gameId.
-- Fehlerbehandlung: Scheitert LogOnboardingFunnelStepEvent, wirft sink weiter (Analytics wertet das Event als
-- nicht gesendet und versucht den Schritt spaeter erneut). Scheitert danach LogCustomEvent, wirft sink NICHT,
-- sondern warnt gedrosselt: Ein Wiederholen wuerde den Onboarding-Schritt doppelt senden, und ein doppelter
-- Funnel-Schritt verfaelscht den Funnel staerker als ein fehlendes Custom Event. Ohne funnelStep wird ein
-- LogCustomEvent-Fehler weitergeworfen (dann gibt es keinen Doppel-Effekt).
-- Die Methoden brauchen das Player-Objekt; ist der Spieler nicht mehr da, wird das Event ohne Fehler verworfen.
-- Doku: https://create.roblox.com/docs/reference/engine/classes/AnalyticsService
--       https://create.roblox.com/docs/production/analytics/funnel-events
--       https://create.roblox.com/docs/production/analytics/custom-events
local Log = require(script.Parent.Parent.Parent.shared.Log)

export type Options = {
	findPlayer: (userId: number) -> any,
	analyticsService: any?,
	log: Log.Log?,
}

export type AnalyticsAdapter = {
	sink: (eventName: string, fields: { [string]: any }) -> (),
}

local AnalyticsAdapter = {}

function AnalyticsAdapter.new(options: Options): AnalyticsAdapter
	assert(type(options.findPlayer) == "function", "AnalyticsAdapter: findPlayer must be a function")
	local service: any = options.analyticsService or game:GetService("AnalyticsService")
	local findPlayer = options.findPlayer
	local log = options.log or Log.new()
	local keys = Enum.AnalyticsCustomFieldKeys

	local adapter: AnalyticsAdapter = {
		sink = function(eventName: string, fields: { [string]: any })
			local player = findPlayer(fields.userId)
			if player == nil then
				return
			end
			local customFields: { [string]: any } = {
				[keys.CustomField01.Name] = fields.configVersion,
				[keys.CustomField03.Name] = fields.gameId,
			}
			local label = fields.source or fields.role
			if label ~= nil then
				customFields[keys.CustomField02.Name] = tostring(label)
			end
			local value = 1
			if eventName == "session_end" and type(fields.durationSeconds) == "number" then
				value = fields.durationSeconds
			elseif eventName == "zone_unlock" and type(fields.zoneIndex) == "number" then
				value = fields.zoneIndex
			end
			if type(fields.funnelStep) ~= "number" then
				service:LogCustomEvent(player, eventName, value, customFields)
				return
			end
			-- Wirft weiter: dann gilt das Event als nicht gesendet.
			service:LogOnboardingFunnelStepEvent(player, fields.funnelStep, eventName, customFields)
			local ok, err = pcall(function()
				service:LogCustomEvent(player, eventName, value, customFields)
			end)
			if not ok then
				log:warnThrottled(
					"custom:" .. eventName,
					"[AnalyticsAdapter] LogCustomEvent failed after funnel step: " .. tostring(err)
				)
			end
		end,
	}
	return adapter
end

return AnalyticsAdapter
