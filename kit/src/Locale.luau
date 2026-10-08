--!strict
-- Sprachwahl fuer die Texte des Games: Die ClientConfig liefert je Sprache einen Textsatz
-- (textsByLanguage = { [sprache] = { [schluessel] = text } }); das Kit enthaelt selbst keine Texte.
--
-- languageFor(localeId, available, default): Sprache aus der Spieler-Locale (z. B. "de-de" -> "de",
-- "en-us" -> "en"); nicht vorhandene Sprachen -> default. Gross-/Kleinschreibung und "_" statt "-" egal.
-- texts(sets, language, default, onMissing?): flacher Textsatz der gewaehlten Sprache; fehlt dort ein Schluessel, kommt
-- er aus default (bzw. umgekehrt) und es gibt je Schluessel genau eine Warnung (gedrosselt: nie wiederholt).
-- missingKeys(sets): je Sprache die Schluessel, die eine andere Sprache hat und diese nicht (fuer Tests).
-- localeOf(player, service?): Locale des lokalen Spielers. Reihenfolge: Translator aus
-- LocalizationService:GetTranslatorForPlayerAsync (empfohlen laut Doku), sonst RobloxLocaleId, sonst
-- Player.LocaleId; alles in pcall, Rueckfall "en-us".
-- Doku: https://create.roblox.com/docs/reference/engine/classes/LocalizationService#GetTranslatorForPlayerAsync
--       https://create.roblox.com/docs/reference/engine/classes/LocalizationService#RobloxLocaleId
--       https://create.roblox.com/docs/reference/engine/classes/Player#LocaleId
--       https://create.roblox.com/docs/reference/engine/classes/Translator#LocaleId
local Locale = {}

export type Sets = { [string]: { [string]: string } }

local warned: { [string]: boolean } = {}

function Locale.languageFor(localeId: string?, available: Sets, default: string): string
	if type(localeId) ~= "string" then
		return default
	end
	local language = string.lower(string.match(localeId, "^%a+") or "")
	return if available[language] ~= nil then language else default
end

function Locale.texts(
	sets: Sets,
	language: string,
	default: string,
	onMissing: ((message: string) -> ())?
): { [string]: string }
	local primary = sets[language] or sets[default] or {}
	local fallback = sets[default] or {}
	local report = onMissing or function(message: string)
		warn(message)
	end
	local result: { [string]: string } = table.clone(primary)
	local function fill(from: { [string]: string }, fromLanguage: string)
		for key, value in from do
			if result[key] == nil then
				result[key] = value
				local id = language .. ":" .. key
				if not warned[id] then
					warned[id] = true
					report(string.format("[Locale] %q fehlt in %s, nehme %s", key, language, fromLanguage))
				end
			end
		end
	end
	fill(fallback, default)
	-- Auch Schluessel, die nur in anderen Sprachen stehen, sollen nie als roher Schluessel erscheinen.
	local others = {}
	for other in sets do
		if other ~= language and other ~= default then
			table.insert(others, other)
		end
	end
	table.sort(others)
	for _, other in others do
		fill(sets[other], other)
	end
	return result
end

function Locale.missingKeys(sets: Sets): { [string]: { string } }
	local all: { [string]: boolean } = {}
	for _, set in sets do
		for key in set do
			all[key] = true
		end
	end
	local missing: { [string]: { string } } = {}
	for language, set in sets do
		local list = {}
		for key in all do
			if set[key] == nil then
				table.insert(list, key)
			end
		end
		table.sort(list)
		missing[language] = list
	end
	return missing
end

function Locale.localeOf(player: any, service: any?): string
	local localization = service or game:GetService("LocalizationService")
	local ok, translator = pcall(function()
		return localization:GetTranslatorForPlayerAsync(player)
	end)
	if ok and translator ~= nil and type(translator.LocaleId) == "string" and translator.LocaleId ~= "" then
		return translator.LocaleId
	end
	for _, read in
		{
			function()
				return localization.RobloxLocaleId
			end,
			function()
				return player.LocaleId
			end,
		}
	do
		local found, value = pcall(read)
		if found and type(value) == "string" and value ~= "" then
			return value
		end
	end
	return "en-us"
end

-- Nur fuer Tests: Warnungs-Gedaechtnis zuruecksetzen.
function Locale.resetWarnings()
	table.clear(warned)
end

return Locale
