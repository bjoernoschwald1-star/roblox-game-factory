--!strict
-- StorageAdapter im Arbeitsspeicher, nur fuer Tests. Werte werden beim Schreiben und Lesen kopiert,
-- damit sich Aufrufer und "Speicher" wie bei einem echten DataStore keine Tabellen teilen.
--
-- Fehlereinspeisung:
--   failReads(n)             die naechsten n read-Aufrufe schlagen fehl
--   failUpdates(n)           die naechsten n update-Aufrufe schlagen fehl, ohne zu schreiben
--   failUpdatesAfterWrite(n) die naechsten n update-Aufrufe schreiben, melden aber trotzdem einen Fehler
--                            (Write-Status unbekannt); failUpdates hat Vorrang
-- Hilfen: seed(key, value) setzt einen Eintrag ohne Zaehlung, peek(key) liefert eine Kopie,
-- stats zaehlt Aufrufe und tatsaechliche Schreibvorgaenge.
local TableCopy = require(script.Parent.Parent.shared.TableCopy)

export type Stats = {
	reads: number,
	updates: number,
	removes: number,
	writes: number,
}

export type MemoryAdapter = {
	read: (self: MemoryAdapter, key: string) -> (boolean, any),
	update: (self: MemoryAdapter, key: string, transform: (old: any) -> any) -> (boolean, any),
	remove: (self: MemoryAdapter, key: string) -> (boolean, any),
	failReads: (self: MemoryAdapter, count: number) -> (),
	failUpdates: (self: MemoryAdapter, count: number) -> (),
	failUpdatesAfterWrite: (self: MemoryAdapter, count: number) -> (),
	seed: (self: MemoryAdapter, key: string, value: any) -> (),
	peek: (self: MemoryAdapter, key: string) -> any,
	stats: Stats,
}

local MemoryAdapter = {}

function MemoryAdapter.new(): MemoryAdapter
	local data: { [string]: any } = {}
	local pendingReadFailures = 0
	local pendingUpdateFailures = 0
	local pendingFailuresAfterWrite = 0
	local stats: Stats = { reads = 0, updates = 0, removes = 0, writes = 0 }

	local adapter: MemoryAdapter = {
		read = function(_self, key: string): (boolean, any)
			stats.reads += 1
			if pendingReadFailures > 0 then
				pendingReadFailures -= 1
				return false, "MemoryAdapter: simulated read failure"
			end
			return true, TableCopy.copy(data[key])
		end,

		update = function(_self, key: string, transform: (old: any) -> any): (boolean, any)
			stats.updates += 1
			if pendingUpdateFailures > 0 then
				pendingUpdateFailures -= 1
				return false, "MemoryAdapter: simulated update failure"
			end
			local ok, newValue = pcall(transform, TableCopy.copy(data[key]))
			if not ok then
				return false, newValue
			end
			if newValue ~= nil then
				data[key] = TableCopy.copy(newValue)
				stats.writes += 1
			end
			if pendingFailuresAfterWrite > 0 then
				pendingFailuresAfterWrite -= 1
				return false, "MemoryAdapter: simulated failure after write (status unknown)"
			end
			return true, TableCopy.copy(newValue)
		end,

		remove = function(_self, key: string): (boolean, any)
			stats.removes += 1
			local old = data[key]
			data[key] = nil
			return true, old
		end,

		failReads = function(_self, count: number)
			pendingReadFailures = count
		end,

		failUpdates = function(_self, count: number)
			pendingUpdateFailures = count
		end,

		failUpdatesAfterWrite = function(_self, count: number)
			pendingFailuresAfterWrite = count
		end,

		seed = function(_self, key: string, value: any)
			data[key] = TableCopy.copy(value)
		end,

		peek = function(_self, key: string): any
			return TableCopy.copy(data[key])
		end,

		stats = stats,
	}
	return adapter
end

return MemoryAdapter
