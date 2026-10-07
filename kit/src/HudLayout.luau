--!strict
-- Reine Layout-Logik des HUD (Mobile zuerst). Alle Positionen und Groessen sind Skalenwerte (UDim2.fromScale)
-- relativ zur GUI-Flaeche; UISizeConstraint begrenzt Min-/Maxgroesse in Pixeln (Touch-Ziele mindestens
-- MIN_TOUCH_SIZE hoch). Die GUI-Flaeche ist der CoreUISafeInsets-Bereich (ScreenGui.ScreenInsets, Standard bei
-- IgnoreGuiInset = false): ohne Topbar und Geraete-Aussparungen.
--
-- Drei Vorlagen nach Groesse der Flaeche: "portrait" (Hochformat-Handy), "landscape" (Querformat-Handy) und "wide"
-- (Flaeche ab 1000 px Breite, z. B. Desktop). Freihaltezonen (reserved): Chat oben links, Sprungknopf unten rechts,
-- Thumbstick unten links und - ab einer kleineren Bildschirmkante ueber 500 px (Desktop/Tablet, wo die Roblox-
-- Spielerliste mit leaderstats standardmaessig offen ist) - die Spielerliste oben rechts (340 px breit). Die Doku
-- nennt fuer die Touch-Steuerung nur "a portion of the bottom-left and bottom-right corners" und fuer das
-- Chatfenster keine Pixelgroesse; die Zonen hier sind daher bewusst grosszuegig gewaehlt und werden im Spieltest
-- gegen die echten AbsoluteSize-Werte (ChatWindowConfiguration, TouchGui.JumpButton) geprueft.
-- Entscheidung Aktions-Buttons: rechts ueber dem Sprungknopf (Hochformat) bzw. rechts oben neben dem Inventar
-- (Querformat). Der rechte Daumen liegt ohnehin dort (Sprung); links bleibt fuer den Thumbstick frei, und Buttons
-- im Thumbstick-Bereich wuerden Laufbewegungen abfangen.
-- Doku: https://create.roblox.com/docs/ui/position-and-size#reserved-zones
--       https://create.roblox.com/docs/reference/engine/classes/ScreenGui#ScreenInsets
--       https://create.roblox.com/docs/reference/engine/classes/UISizeConstraint
--       https://create.roblox.com/docs/chat/chat-window#chat-window-configuration

export type Spec = {
	position: Vector2, -- Skalenwerte
	size: Vector2, -- Skalenwerte
	anchor: Vector2,
	minSize: Vector2,
	maxSize: Vector2,
}

export type Rect = { x: number, y: number, w: number, h: number }

local MIN_TOUCH_SIZE = 64
local INF = math.huge
local LABEL_MAX = Vector2.new(360, 48)
local BUTTON_MAX = Vector2.new(360, 80)

local HudLayout = {}

HudLayout.MIN_TOUCH_SIZE = MIN_TOUCH_SIZE
HudLayout.BUTTONS = { "unlock", "collect", "sell" } -- dazu upgrade:<dim>

local function spec(
	px: number,
	py: number,
	sx: number,
	sy: number,
	ax: number,
	ay: number,
	minX: number,
	minY: number,
	max: Vector2
): Spec
	return {
		position = Vector2.new(px, py),
		size = Vector2.new(sx, sy),
		anchor = Vector2.new(ax, ay),
		minSize = Vector2.new(minX, minY),
		maxSize = max,
	}
end

function HudLayout.presetFor(area: Vector2): string
	if area.X > 0 and area.Y > 0 and area.X < area.Y then
		return "portrait"
	end
	return if area.X >= 1000 then "wide" else "landscape"
end

-- Vorlagen je Element: coins, inventory, zoneHint, unlock, collect, sell, hint, upgrade1..n.
function HudLayout.specs(preset: string, upgradeCount: number): { [string]: Spec }
	local specs: { [string]: Spec } = {}
	if preset == "portrait" then
		specs.coins = spec(0.98, 0.01, 0.5, 0.06, 1, 0, 180, 36, LABEL_MAX)
		specs.inventory = spec(0.98, 0.08, 0.5, 0.06, 1, 0, 180, 36, LABEL_MAX)
		specs.zoneHint = spec(0.98, 0.15, 0.5, 0.05, 1, 0, 180, 30, LABEL_MAX)
		specs.unlock = spec(0.98, 0.21, 0.5, 0.09, 1, 0, 160, MIN_TOUCH_SIZE, BUTTON_MAX)
		specs.hint = spec(0.5, 0.32, 0.9, 0.08, 0.5, 0, 0, 48, Vector2.new(INF, 80))
		specs.collect = spec(0.98, 0.735, 0.4, 0.09, 1, 1, 140, MIN_TOUCH_SIZE, BUTTON_MAX)
		specs.sell = spec(0.98, 0.835, 0.4, 0.09, 1, 1, 140, MIN_TOUCH_SIZE, BUTTON_MAX)
		for index = 1, upgradeCount do
			specs["upgrade" .. index] =
				spec(0.02, 0.42 + (index - 1) * 0.09, 0.46, 0.085, 0, 0, 150, MIN_TOUCH_SIZE, BUTTON_MAX)
		end
	elseif preset == "wide" then
		-- Rechter Block links neben der Spielerliste, linker Block rechts neben dem Chat.
		specs.zoneHint = spec(0.52, 0.02, 0.2, 0.075, 1, 0, 150, 36, LABEL_MAX)
		specs.unlock = spec(0.52, 0.105, 0.2, 0.12, 1, 0, 150, MIN_TOUCH_SIZE, BUTTON_MAX)
		specs.coins = spec(0.725, 0.02, 0.2, 0.075, 1, 0, 150, 36, LABEL_MAX)
		specs.inventory = spec(0.725, 0.105, 0.2, 0.075, 1, 0, 150, 36, LABEL_MAX)
		specs.collect = spec(0.623, 0.2, 0.098, 0.12, 1, 0, 96, MIN_TOUCH_SIZE, BUTTON_MAX)
		specs.sell = spec(0.725, 0.2, 0.098, 0.12, 1, 0, 96, MIN_TOUCH_SIZE, BUTTON_MAX)
	else
		specs.zoneHint = spec(0.72, 0.02, 0.26, 0.11, 1, 0, 150, 36, LABEL_MAX)
		specs.unlock = spec(0.72, 0.15, 0.26, 0.2, 1, 0, 150, MIN_TOUCH_SIZE, BUTTON_MAX)
		specs.coins = spec(0.98, 0.02, 0.25, 0.11, 1, 0, 150, 36, LABEL_MAX)
		specs.inventory = spec(0.98, 0.15, 0.25, 0.11, 1, 0, 150, 36, LABEL_MAX)
		specs.collect = spec(0.855, 0.28, 0.125, 0.2, 1, 0, 96, MIN_TOUCH_SIZE, BUTTON_MAX)
		specs.sell = spec(0.98, 0.28, 0.12, 0.2, 1, 0, 96, MIN_TOUCH_SIZE, BUTTON_MAX)
	end
	if preset ~= "portrait" then
		specs.hint = spec(0.5, 0.52, 0.56, 0.15, 0.5, 0, 0, 48, Vector2.new(INF, 80))
		local width = 0.6 / math.max(upgradeCount, 1)
		for index = 1, upgradeCount do
			specs["upgrade" .. index] =
				spec(0.21 + (index - 1) * width, 0.97, width - 0.01, 0.2, 0, 1, 96, MIN_TOUCH_SIZE, BUTTON_MAX)
		end
	end
	return specs
end

-- Pixel-Rechteck wie Roblox es berechnet: Groesse = Skala * Flaeche, begrenzt durch Min/Max; Lage minus Anker.
function HudLayout.resolve(s: Spec, area: Vector2): Rect
	local w = math.clamp(s.size.X * area.X, s.minSize.X, math.max(s.minSize.X, s.maxSize.X))
	local h = math.clamp(s.size.Y * area.Y, s.minSize.Y, math.max(s.minSize.Y, s.maxSize.Y))
	return {
		x = s.position.X * area.X - s.anchor.X * w,
		y = s.position.Y * area.Y - s.anchor.Y * h,
		w = w,
		h = h,
	}
end

-- Freihaltezonen in der GUI-Flaeche. screenMin = kleinere Bildschirmkante (Touch-Steuerung skaliert damit).
function HudLayout.reserved(area: Vector2, screenMin: number): { [string]: Rect }
	local chatW = math.min(0.45 * area.X, 400)
	local chatH = math.clamp(0.3 * area.Y, 140, 250)
	local jump = if screenMin <= 500 then 110 else 230
	local thumb = math.clamp(0.4 * screenMin, 150, 260)
	local zones: { [string]: Rect } = {
		chat = { x = 0, y = 0, w = chatW, h = chatH },
		jump = { x = area.X - jump, y = area.Y - jump, w = jump, h = jump },
		thumb = { x = 0, y = area.Y - thumb, w = thumb, h = thumb },
	}
	if screenMin > 500 then
		zones.playerList = { x = area.X - 340, y = 0, w = 340, h = math.clamp(0.35 * area.Y, 150, 300) }
	end
	return zones
end

function HudLayout.overlaps(a: Rect, b: Rect): boolean
	return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

local function sortedKeys(map: { [string]: any }): { string }
	local keys = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

-- Prueft ein Bildschirmformat: liefert alle Konflikte ("a/b") zwischen Elementen, mit Freihaltezonen und mit dem
-- Bildschirmrand. topInset = Hoehe der Topbar (GuiService:GetGuiInset), die nicht zur GUI-Flaeche gehoert.
function HudLayout.check(viewport: Vector2, topInset: number, upgradeCount: number): { string }
	local area = Vector2.new(viewport.X, viewport.Y - topInset)
	local specs = HudLayout.specs(HudLayout.presetFor(area), upgradeCount)
	local rects: { [string]: Rect } = {}
	for name, s in specs do
		rects[name] = HudLayout.resolve(s, area)
	end
	local names = sortedKeys(rects)
	local problems: { string } = {}
	for i, a in names do
		local r = rects[a]
		if r.x < 0 or r.y < 0 or r.x + r.w > area.X or r.y + r.h > area.Y then
			table.insert(problems, a .. "/screen")
		end
		for j = i + 1, #names do
			if HudLayout.overlaps(r, rects[names[j]]) then
				table.insert(problems, a .. "/" .. names[j])
			end
		end
		local zones = HudLayout.reserved(area, math.min(viewport.X, viewport.Y))
		for _, zone in sortedKeys(zones) do
			if HudLayout.overlaps(r, zones[zone]) then
				table.insert(problems, a .. "/" .. zone)
			end
		end
	end
	return problems
end

-- Wendet eine Vorlage auf ein GuiObject an (Skalenwerte plus UISizeConstraint).
function HudLayout.apply(target: GuiObject, s: Spec)
	target.AnchorPoint = s.anchor
	target.Position = UDim2.fromScale(s.position.X, s.position.Y)
	target.Size = UDim2.fromScale(s.size.X, s.size.Y)
	local limit = target:FindFirstChildOfClass("UISizeConstraint")
	if limit == nil then
		local created = Instance.new("UISizeConstraint")
		created.Parent = target
		limit = created
	end
	assert(limit ~= nil, "HudLayout: constraint missing")
	limit.MinSize = s.minSize
	limit.MaxSize = Vector2.new(math.max(s.minSize.X, s.maxSize.X), math.max(s.minSize.Y, s.maxSize.Y))
end

return HudLayout
