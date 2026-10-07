--!strict
-- Licht und Farbe aus Daten: apply(profile, lighting?) setzt Lighting-Eigenschaften und legt bei Bedarf
-- Atmosphere, ColorCorrectionEffect, BloomEffect, SunRaysEffect und Sky an (nur Eigenschaften, keine Bild-Assets).
-- Aufruf durch das Server-Skript des Games; Lighting-Eigenschaften und -Kinder repliziert Roblox zu den Clients.
--
-- profile = { properties = { [Name] = Wert }, atmosphere = {..}, colorCorrection = {..}, bloom = {..},
--   sunRays = {..}, sky = {..} }; jede Gruppe ist optional. Effekt-Instanzen heissen Factory<Klasse> und werden
-- wiederverwendet. Unbekannte Eigenschaften werden nicht still geschluckt: apply liefert (restore, errors) mit
-- je einem Eintrag "Name: Fehler" pro fehlgeschlagener Zuweisung. restore() setzt alle geaenderten Lighting-Werte
-- zurueck und entfernt die angelegten Instanzen (fuer Tests und Spielmodi).
-- Doku: https://create.roblox.com/docs/reference/engine/classes/Lighting
--       https://create.roblox.com/docs/reference/engine/classes/Atmosphere
--       https://create.roblox.com/docs/reference/engine/classes/ColorCorrectionEffect
--       https://create.roblox.com/docs/reference/engine/classes/BloomEffect
--       https://create.roblox.com/docs/reference/engine/classes/SunRaysEffect
--       https://create.roblox.com/docs/reference/engine/classes/Sky

export type Profile = {
	properties: { [string]: any }?,
	atmosphere: { [string]: any }?,
	colorCorrection: { [string]: any }?,
	bloom: { [string]: any }?,
	sunRays: { [string]: any }?,
	sky: { [string]: any }?,
}

local CHILDREN: { { field: string, className: string } } = {
	{ field = "atmosphere", className = "Atmosphere" },
	{ field = "colorCorrection", className = "ColorCorrectionEffect" },
	{ field = "bloom", className = "BloomEffect" },
	{ field = "sunRays", className = "SunRaysEffect" },
	{ field = "sky", className = "Sky" },
}

local LightingProfile = {}

LightingProfile.CHILDREN = CHILDREN

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

function LightingProfile.apply(profile: Profile, lighting: Instance?): (() -> (), { string })
	local target: Instance = lighting or game:GetService("Lighting")
	local errors: { string } = {}
	local previous: { [string]: any } = {}
	local created: { Instance } = {}

	local function assign(instance: Instance, values: { [string]: any }, remember: boolean)
		for _, name in sortedKeys(values) do
			local ok, err = pcall(function()
				if remember and previous[name] == nil then
					previous[name] = (instance :: any)[name]
				end
				(instance :: any)[name] = values[name]
			end)
			if not ok then
				table.insert(errors, string.format("%s.%s: %s", instance.ClassName, name, tostring(err)))
			end
		end
	end

	if profile.properties ~= nil then
		assign(target, profile.properties, true)
	end
	for _, child in CHILDREN do
		local values = (profile :: any)[child.field]
		if type(values) == "table" then
			local name = "Factory" .. child.className
			local found = target:FindFirstChild(name)
			local instance: Instance
			if found ~= nil and found:IsA(child.className) then
				instance = found
			else
				instance = Instance.new(child.className)
				instance.Name = name
				table.insert(created, instance)
			end
			assign(instance, values, false)
			instance.Parent = target
		end
	end

	local function restore()
		for name, value in previous do
			pcall(function()
				(target :: any)[name] = value
			end)
		end
		table.clear(previous)
		for _, instance in created do
			instance:Destroy()
		end
		table.clear(created)
	end
	return restore, errors
end

return LightingProfile
