--!strict
-- Reine Logik des Sammelalbums: macht aus snapshot.collection (Server, nur eigener Stand) und den Anzeige-Daten
-- des Games ein Anzeigemodell. Keine Instanzen, keine Spielentscheidungen.
--
-- display = { groups = { [groupId] = nameKey }, entries = { [entryId] = { nameKey, rarity? } } }.
-- Text-Schluessel (config.texts, Platzhalter in {}): album_title, album_progress {found} {total},
-- album_row_progress {found} {total}, album_reward_coins {coins}, album_reward_bonus {percent},
-- album_reward_done, hud_album. Bonus-Prozent aus mul auf sellFactor ((mul - 1) * 100, ueber Text.decimal).
local Text = require(script.Parent.Text)

export type Cell = {
	entryId: string,
	name: string,
	found: boolean,
	rarity: string?,
}

export type Row = {
	groupId: string,
	name: string,
	progressText: string,
	rewardText: string,
	done: boolean,
	cells: { Cell },
}

export type Model = {
	visible: boolean,
	buttonText: string,
	title: string,
	progressText: string,
	rows: { Row },
}

export type Display = {
	groups: { [string]: string },
	entries: { [string]: { nameKey: string, rarity: string? } },
}

local AlbumModel = {}

local function rewardText(group: any, strings: { [string]: string }): string
	local parts: { string } = {}
	if group.rewardCoins > 0 then
		table.insert(parts, Text.lookup(strings, "album_reward_coins", { coins = group.rewardCoins }))
	end
	local sell = group.rewardEffects and group.rewardEffects.sellFactor
	if sell ~= nil and sell.mul ~= nil and sell.mul ~= 1 then
		table.insert(
			parts,
			Text.lookup(strings, "album_reward_bonus", { percent = Text.decimal((sell.mul - 1) * 100, strings) })
		)
	end
	local text = table.concat(parts, " · ")
	if group.done then
		text = Text.lookup(strings, "album_reward_done") .. (if text ~= "" then " " .. text else "")
	end
	return text
end

function AlbumModel.build(snapshot: any, display: Display?, texts: { [string]: string }?): Model
	local strings = texts or {}
	local collection = if snapshot ~= nil then snapshot.collection else nil
	local model: Model = {
		visible = collection ~= nil,
		buttonText = Text.lookup(strings, "hud_album"),
		title = Text.lookup(strings, "album_title"),
		progressText = "",
		rows = {},
	}
	if collection == nil then
		return model
	end
	local names = if display ~= nil then display else { groups = {}, entries = {} }
	model.progressText =
		Text.lookup(strings, "album_progress", { found = collection.foundCount, total = collection.total })
	local groupIds = {}
	for groupId in collection.groups do
		table.insert(groupIds, groupId)
	end
	table.sort(groupIds, function(a: string, b: string): boolean
		return collection.groups[a].order < collection.groups[b].order
	end)
	for _, groupId in groupIds do
		local group = collection.groups[groupId]
		local cells: { Cell } = {}
		for _, entryId in group.entries do
			local entry = names.entries[entryId]
			table.insert(cells, {
				entryId = entryId,
				name = Text.lookup(strings, if entry then entry.nameKey else entryId),
				found = collection.found[entryId] == true,
				rarity = if entry then entry.rarity else nil,
			})
		end
		table.insert(model.rows, {
			groupId = groupId,
			name = Text.lookup(strings, names.groups[groupId] or groupId),
			progressText = Text.lookup(strings, "album_row_progress", { found = group.found, total = #group.entries }),
			rewardText = rewardText(group, strings),
			done = group.done,
			cells = cells,
		})
	end
	return model
end

return AlbumModel
