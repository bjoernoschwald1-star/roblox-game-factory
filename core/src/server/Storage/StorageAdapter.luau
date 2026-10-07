--!strict
-- Austauschbare Speicher-Schnittstelle. Der Core greift ausschliesslich hierueber auf Persistenz zu.
-- Keine Methode wirft: Fehler kommen als (false, Fehlermeldung) zurueck.
--
-- read(key)              -> (true, Wert oder nil)        | (false, Fehler)
-- update(key, transform) -> (true, neuer Wert oder nil)  | (false, Fehler)
--     transform(alt) liefert den neuen Wert; liefert sie nil, wird nichts geschrieben.
--     transform kann mehrfach aufgerufen werden und darf nicht yielden.
-- remove(key)            -> (true, alter Wert oder nil)  | (false, Fehler)

export type StorageAdapter = {
	read: (self: StorageAdapter, key: string) -> (boolean, any),
	update: (self: StorageAdapter, key: string, transform: (old: any) -> any) -> (boolean, any),
	remove: (self: StorageAdapter, key: string) -> (boolean, any),
}

return {}
