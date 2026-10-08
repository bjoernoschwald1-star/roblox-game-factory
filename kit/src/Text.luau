--!strict
-- Kleine Text-Hilfe des Kits: Platzhalter {name} in Texten aus der Game-Config ersetzen. Fehlt ein Text,
-- wird der Schluessel selbst angezeigt (sichtbar statt still leer).

local Text = {}

function Text.format(template: string?, values: { [string]: any }?): string
	if type(template) ~= "string" then
		return ""
	end
	local result = string.gsub(template, "{([%w_]+)}", function(name: string): string?
		local value = values and values[name]
		return if value ~= nil then tostring(value) else nil
	end)
	return result
end

-- Zahl fuer die Anzeige: hoechstens zwei Nachkommastellen, ohne Nullen am Ende; Dezimaltrennzeichen aus
-- texts.decimal_separator (Standard ".").
function Text.decimal(value: number, texts: { [string]: string }?): string
	local formatted = string.format("%.2f", value)
	formatted = string.gsub(formatted, "0+$", "")
	formatted = string.gsub(formatted, "%.$", "")
	local separator = if texts ~= nil and type(texts.decimal_separator) == "string"
		then texts.decimal_separator
		else "."
	return (string.gsub(formatted, "%.", separator))
end

function Text.lookup(texts: { [string]: string }?, key: string, values: { [string]: any }?): string
	local template = if texts ~= nil then texts[key] else nil
	return Text.format(template or key, values)
end

return Text
