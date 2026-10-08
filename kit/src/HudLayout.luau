--!strict
-- Reine Layout-Logik des HUD: kompakt an den Raendern, Bildschirmmitte frei (Vorbild: verbreitete Simulator-HUDs).
-- Alle Positionen und Groessen sind Skalenwerte relativ zur GUI-Flaeche (UDim2.fromScale); UISizeConstraint haelt
-- die Pixelgroesse fest (Min = Max), damit Knoepfe am PC klein und auf dem Handy daumengross sind. Die GUI-Flaeche
-- ist der CoreUISafeInsets-Bereich (ScreenGui.ScreenInsets bei IgnoreGuiInset = false): ohne Topbar.
--
-- Vorlagen nach Groesse der GUI-Flaeche (klein = kleinere Kante <= 500 px, also Handy):
--   "portrait" / "landscape" (Handy), "tabletPortrait" / "tablet" (kleinere Kante > 500 px, Breite < 1240 px) und
--   "wide" (ab 1240 px Breite: Laptop/Desktop ohne Touch-Steuerung).
-- Freihaltezonen (reserved), in GUI-Koordinaten:
--   Chat oben links: min(500, 0,5 x Breite) x min(260, 0,35 x Hoehe). Gemessen im Studio-Spieltest mit
--     TextChatService (1736x793): Chatfenster 8,12 / 475x184, Eingabeleiste 16,196 / 459x45.
--   Spielerliste oben rechts (nur grosse Flaechen): 340 x 340, gemessen 320 x 312.
--   Sprungknopf unten rechts (110 bzw. 230 px) und Thumbstick unten links (0,4 x kleinere Kante, 150-260 px) nur
--     auf Touch-Flaechen (alle Vorlagen ausser "wide"); die Doku nennt nur "a portion of the bottom-left and
--     bottom-right corners".
-- Anordnung:
--   Anzeigen (Muenzen, Ladung) kompakt rechts neben dem Chat; ist dort zu wenig Platz, unter dem Chat.
--   Hinweis: klein, oben (neben bzw. unter den Anzeigen), nie in der Bildschirmmitte; OnboardingView blendet ihn
--     nach einigen Sekunden aus.
--   Aktionen (Einsammeln, Verkaufen): runde Knoepfe unten rechts, auf Touch-Flaechen direkt links neben dem
--     Sprungknopf. Groesse 80 px (PC), 72 px (Handy), 88 px (Tablet), damit die Beschriftung lesbar ist.
--   Rand-Knoepfe "unlock" (Zone freischalten) und "upgrades" (oeffnet das Upgrade-Fenster): unten links, auf
--     Touch-Flaechen rechts neben dem Thumbstick bzw. (Handy hoch) ueber ihm.
--   Rand-Knopf "prestige" (nur sichtbar, wenn Prestige moeglich ist): direkt ueber dem hoeheren der beiden
--     Rand-Knoepfe, gleiche Breite.
--   Upgrade-Fenster ("window"): klein und mittig, nur auf Knopfdruck sichtbar; es ueberdeckt keine Anzeigen und
--     Knoepfe (windowRect), darf als modales Fenster aber Freihaltezonen ueberdecken.
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

local MIN_TOUCH_SIZE = 56
local MARGIN = 8
local SMALL_EDGE = 500
local WIDE_WIDTH = 1240
local PLAYER_LIST = 340

-- Beispielflaechen, wenn specs ohne Flaeche aufgerufen wird (z. B. im Test-Container).
local DEFAULT_AREAS: { [string]: Vector2 } = {
	portrait = Vector2.new(456, 726),
	landscape = Vector2.new(844, 332),
	tabletPortrait = Vector2.new(768, 966),
	tablet = Vector2.new(1024, 710),
	wide = Vector2.new(1280, 662),
}

local HudLayout = {}

HudLayout.MIN_TOUCH_SIZE = MIN_TOUCH_SIZE
HudLayout.ELEMENTS = { "coins", "inventory", "hint", "unlock", "upgrades", "prestige", "collect", "sell" }

function HudLayout.presetFor(area: Vector2): string
	if math.min(area.X, area.Y) <= SMALL_EDGE then
		return if area.X > 0 and area.X < area.Y then "portrait" else "landscape"
	end
	if area.X >= WIDE_WIDTH then
		return "wide"
	end
	return if area.X < area.Y then "tabletPortrait" else "tablet"
end

-- Freihaltezonen in der GUI-Flaeche (Werte und Quellen im Kopfkommentar).
function HudLayout.reserved(area: Vector2): { [string]: Rect }
	local edge = math.min(area.X, area.Y)
	local zones: { [string]: Rect } = {
		chat = { x = 0, y = 0, w = math.min(500, 0.5 * area.X), h = math.min(260, 0.35 * area.Y) },
	}
	if HudLayout.presetFor(area) ~= "wide" then
		local jump = if edge <= SMALL_EDGE then 110 else 230
		local thumb = math.clamp(0.4 * edge, 150, 260)
		zones.jump = { x = area.X - jump, y = area.Y - jump, w = jump, h = jump }
		zones.thumb = { x = 0, y = area.Y - thumb, w = thumb, h = thumb }
	end
	if edge > SMALL_EDGE then
		zones.playerList = { x = area.X - PLAYER_LIST, y = 0, w = PLAYER_LIST, h = PLAYER_LIST }
	end
	return zones
end

-- Upgrade-Fenster: moeglichst gross (hoechstens WINDOW_SIZES[1]), mittig und ohne Ueberdeckung von Anzeigen,
-- Hinweis und Knoepfen; passt es mittig nicht, wird es senkrecht verschoben (kleinster Versatz zuerst), sonst
-- kleiner. Freihaltezonen (Chat usw.) darf das modale Fenster ueberdecken.
local WINDOW_SIZES = {
	Vector2.new(340, 260),
	Vector2.new(320, 240),
	Vector2.new(300, 220),
	Vector2.new(280, 200),
	Vector2.new(260, 190),
	Vector2.new(240, 180),
	Vector2.new(220, 170),
}

function HudLayout.windowRect(area: Vector2, rects: { [string]: Rect }): Rect
	local others: { Rect } = {}
	for _, name in { "coins", "inventory", "hint", "unlock", "upgrades", "prestige", "collect", "sell" } do
		if rects[name] ~= nil then
			table.insert(others, rects[name])
		end
	end
	local function free(candidate: Rect): boolean
		if candidate.y < MARGIN or candidate.y + candidate.h > area.Y - MARGIN then
			return false
		end
		for _, other in others do
			if HudLayout.overlaps(candidate, other) then
				return false
			end
		end
		return true
	end
	local offsets = { 0 }
	for step = 10, 200, 10 do
		table.insert(offsets, -step)
		table.insert(offsets, step)
	end
	local last: Rect? = nil
	for _, size in WINDOW_SIZES do
		local w = math.min(size.X, area.X - 2 * MARGIN)
		local h = math.min(size.Y, area.Y - 2 * MARGIN)
		for _, dy in offsets do
			local candidate = { x = (area.X - w) / 2, y = (area.Y - h) / 2 + dy, w = w, h = h }
			if free(candidate) then
				return candidate
			end
		end
		last = { x = (area.X - w) / 2, y = (area.Y - h) / 2, w = w, h = h }
	end
	return last :: Rect
end

-- Pixel-Rechtecke aller Elemente fuer eine Flaeche (Grundlage fuer specs).
function HudLayout.rects(area: Vector2): { [string]: Rect }
	local preset = HudLayout.presetFor(area)
	local zones = HudLayout.reserved(area)
	local touch = preset ~= "wide"
	local phone = math.min(area.X, area.Y) <= SMALL_EDGE
	local labelH = if touch then 34 else 30
	local action = if not touch then 80 elseif phone then 72 else 88
	local buttonH = if touch then 56 else 40
	local chat = zones.chat
	local right = area.X - (if zones.playerList then PLAYER_LIST else 0) - MARGIN
	local rects: { [string]: Rect } = {}

	-- Anzeigen
	local span = right - (chat.w + MARGIN)
	local sx, sw, sy
	if span >= 110 then
		sx, sw, sy = chat.w + MARGIN, math.min(180, span), MARGIN
	else
		sx, sw, sy = MARGIN, 170, chat.h + MARGIN
	end
	rects.coins = { x = sx, y = sy, w = sw, h = labelH }
	rects.inventory = { x = sx, y = sy + labelH + 4, w = sw, h = labelH }
	local statsBottom = sy + 2 * labelH + 4

	-- Hinweis
	local hintH = 30
	if span >= sw + MARGIN + 200 then
		local hx = sx + sw + MARGIN
		rects.hint = { x = hx, y = sy, w = math.min(440, right - hx), h = hintH }
	elseif span >= 300 then
		local hw = math.min(440, span)
		rects.hint = { x = chat.w + MARGIN + (span - hw) / 2, y = statsBottom + 6, w = hw, h = hintH }
	else
		local hy = math.max(chat.h, statsBottom) + 6
		local limit = math.min(right, area.X / 2 - 58)
		if limit - MARGIN >= 220 then
			rects.hint = { x = MARGIN, y = hy, w = math.min(440, limit - MARGIN), h = hintH }
		else
			local avail = right - MARGIN
			local hw = math.min(440, avail)
			rects.hint = { x = MARGIN + (avail - hw) / 2, y = hy, w = hw, h = hintH }
		end
	end

	-- Aktionen und Rand-Knoepfe
	local bottom = area.Y - MARGIN
	if touch then
		local jumpX = zones.jump.x
		rects.sell = { x = jumpX - MARGIN - action, y = bottom - action, w = action, h = action }
		rects.collect = { x = jumpX - 2 * (MARGIN + action), y = bottom - action, w = action, h = action }
		local buttonW = if phone then 96 else 110
		local left = zones.thumb.w + MARGIN
		if rects.collect.x - MARGIN - left >= 2 * buttonW + MARGIN then
			rects.unlock = { x = left, y = bottom - buttonH, w = buttonW, h = buttonH }
			rects.upgrades = { x = left + buttonW + MARGIN, y = bottom - buttonH, w = buttonW, h = buttonH }
		else
			local top = zones.thumb.y - MARGIN
			rects.upgrades = { x = MARGIN, y = top - buttonH, w = buttonW, h = buttonH }
			rects.unlock = { x = MARGIN, y = top - 2 * buttonH - MARGIN, w = buttonW, h = buttonH }
		end
	else
		rects.sell = { x = area.X - MARGIN - action, y = bottom - action, w = action, h = action }
		rects.collect = { x = area.X - 2 * (MARGIN + action), y = bottom - action, w = action, h = action }
		rects.unlock = { x = MARGIN, y = bottom - buttonH, w = 150, h = buttonH }
		rects.upgrades = { x = 2 * MARGIN + 150, y = bottom - buttonH, w = 120, h = buttonH }
	end
	local upper = if rects.unlock.y <= rects.upgrades.y then rects.unlock else rects.upgrades
	rects.prestige = { x = upper.x, y = upper.y - buttonH - MARGIN, w = upper.w, h = buttonH }
	rects.window = HudLayout.windowRect(area, rects)
	return rects
end

-- Vorlagen je Element (Skalenwerte plus feste Pixelgroesse); area optional (sonst Beispielflaeche der Vorlage).
function HudLayout.specs(preset: string, _upgradeCount: number?, area: Vector2?): { [string]: Spec }
	local surface = area
	if surface == nil or surface.X <= 0 or surface.Y <= 0 then
		surface = DEFAULT_AREAS[preset] or DEFAULT_AREAS.landscape
	end
	local resolved = surface :: Vector2
	local specs: { [string]: Spec } = {}
	for name, r in HudLayout.rects(resolved) do
		local size = Vector2.new(r.w, r.h)
		specs[name] = {
			position = Vector2.new(r.x / resolved.X, r.y / resolved.Y),
			size = Vector2.new(r.w / resolved.X, r.h / resolved.Y),
			anchor = Vector2.zero,
			minSize = size,
			maxSize = size,
		}
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

-- Prueft ein Bildschirmformat: alle Konflikte ("a/b") zwischen Elementen, mit Freihaltezonen, mit dem Rand und mit
-- der Bildschirmmitte ("center", Figur). topInset = Hoehe der Topbar (GuiService:GetGuiInset).
function HudLayout.check(viewport: Vector2, topInset: number, upgradeCount: number?): { string }
	local area = Vector2.new(viewport.X, viewport.Y - topInset)
	local specs = HudLayout.specs(HudLayout.presetFor(area), upgradeCount, area)
	local rects: { [string]: Rect } = {}
	for _, name in HudLayout.ELEMENTS do
		rects[name] = HudLayout.resolve(specs[name], area)
	end
	local zones = HudLayout.reserved(area)
	zones.center = { x = area.X / 2 - 50, y = viewport.Y / 2 - topInset - 40, w = 100, h = 120 }
	local names = sortedKeys(rects)
	local problems: { string } = {}
	-- Das modale Upgrade-Fenster darf keine Anzeigen und Knoepfe ueberdecken.
	local window = HudLayout.resolve(specs.window, area)
	for _, name in names do
		if HudLayout.overlaps(window, rects[name]) then
			table.insert(problems, "window/" .. name)
		end
	end
	for i, a in names do
		local r = rects[a]
		if r.x < 0 or r.y < 0 or r.x + r.w > area.X + 1e-6 or r.y + r.h > area.Y + 1e-6 then
			table.insert(problems, a .. "/screen")
		end
		for j = i + 1, #names do
			if HudLayout.overlaps(r, rects[names[j]]) then
				table.insert(problems, a .. "/" .. names[j])
			end
		end
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
