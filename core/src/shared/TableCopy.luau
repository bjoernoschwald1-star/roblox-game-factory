--!strict
-- Rekursive Tabellenkopie: Gespeicherte und im Speicher gehaltene Staende teilen sich nie eine Tabelle.

local TableCopy = {}

function TableCopy.copy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for k, v in value :: any do
		copy[TableCopy.copy(k)] = TableCopy.copy(v)
	end
	return (copy :: any) :: T
end

return TableCopy
