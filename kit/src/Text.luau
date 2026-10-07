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

function Text.lookup(texts: { [string]: string }?, key: string, values: { [string]: any }?): string
	local template = if texts ~= nil then texts[key] else nil
	return Text.format(template or key, values)
end

return Text
