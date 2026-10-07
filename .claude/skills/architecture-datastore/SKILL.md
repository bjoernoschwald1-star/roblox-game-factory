---
name: architecture-datastore
description: Modulschnitt der Core Engine, Dependency Injection und Persistenz. Verwenden, wenn ein Server-Modul in core/src angelegt oder geändert wird, Profilfelder, ProfileStore, PlayerSession, Migrationen oder Session-Locks betroffen sind, GameServer.compose oder ServerRuntime verdrahtet werden oder der Rückweg zum Client (StateSync) geändert wird.
---

# Architektur und Datenhaltung

## Modulschnitt (core/src/server)
- Fachmodule ohne Roblox-Dienste: `Economy`, `Inventory`, `Collecting` (+ `CollectTypes/Radius`), `Modifiers`,
  `Upgrades`, `Zones`, `Selling`, `Monetization`, `Analytics`, `RemoteGateway`, `StateSync`.
- Persistenz: `ProfileStore` (laden, speichern, sperren, migrieren) und `PlayerSession` (geladene Profile pro
  userId; join/get/save/autosaveAll/leave/shutdown). Speicherzugriff nur über `Storage/StorageAdapter`.
- Zusammensetzen: `GameServer.compose(config, services)` – validiert, kopiert die Config, baut alle Module und
  registriert die vier Remotes. Keine Schleifen, keine Timer, keine Roblox-Dienste.
- Engine-Anbindung: `Engine/ServerRuntime.start(config, options)` plus Adapter (`PlayersAdapter`,
  `CharacterAdapter`, `RemoteBinder`, `WorldAdapter`, `MarketAdapter`, `AnalyticsAdapter`, `Scheduler`).
  Nur hier sind Players, RemoteEvent, MarketplaceService, DataStoreService, BindToClose erlaubt.
- Gemeinsam: `core/src/shared/` (`PlayerContext`, `TableCopy`, `Log`).

## Injektion
- Jedes Modul bekommt seine Abhängigkeiten im Konstruktor (`X.new(options)`): Uhr (`clock`), `sleep`, `rng`,
  `getProfile`, `log`, Callbacks. Beispiel: `Services` in `core/src/server/GameServer.luau`.
- Pflichtoptionen per `assert` prüfen (Programmierfehler); Laufzeitfehler als `(ok, err)`.
- Neue Roblox-Abhängigkeit = neuer oder erweiterter Adapter in `Engine/` mit Fake in den Tests
  (siehe `core/tests/EngineAdaptersSpec.luau`, `core/tests/ServerRuntimeSpec.luau`).

## ProfileStore-Regeln (`core/src/server/ProfileStore.luau`)
- Geschrieben wird ausschließlich über `storage:update` (UpdateAsync); jede Schreibentscheidung fällt atomar im
  transform anhand des tatsächlich gespeicherten Eintrags. Nie SetAsync, nie blind überschreiben.
- Ein Speicherfehler ersetzt nie einen vorhandenen Stand durch ein Standardprofil.
- Lade-Zustände: `NEW` (kein Eintrag, Defaults), `LOADED`, `LOCKED` (frischer fremder Lock innerhalb
  `lockTtlSeconds`, Standard 600 s, nach `lockWait`-Versuchen), `FAILED` (Speicherfehler, `INVALID_ENTRY`,
  `MIGRATION_ERROR`), `FUTURE_VERSION` (gespeicherte schemaVersion > eigene; nie herabstufen).
- Session-Lock `session = { serverId, timestamp }`; `save` und `release` liefern `LOCK_LOST`, wenn ein anderer
  Server den Lock hält. Ein Lock ohne gültigen Zeitstempel gilt als veraltet.
- Retry mit wachsendem Abstand (`retry`, Standard 3 Versuche, 1 s Basis).
- Migrationen: `migrations[n]` hebt von Version n auf n + 1, läuft in pcall auf einer Kopie; Fehler -> `FAILED`.
  Migrationen eines Live-DataStores sind ein manuelles Gate (Björn).
- Bekannte offene Punkte stehen im Kopfkommentar von `ProfileStore.luau`; bei Änderungen aktualisieren.

## Profilfelder
- Core garantiert: `schemaVersion`, `firstSeen`, `lastSeen`, `session`.
- Game-Defaults aus `GameServer.compose`: `coins`, `inventory`, `upgrades`, `zones`, `purchases`, `perks`,
  `funnel`. Jedes Modul arbeitet nur auf seinem Feld (Feldname als Option, z. B. `field = "purchases"`).
- Fehlendes Feld anlegen; vorhandener, falsch typisierter Wert -> `CORRUPT_VALUE`, nichts ändern.
- Nur Spielstand ins Profil; abgeleitete Werte (Modifier, Pass-Effekte, Cache) nie speichern.

## GameServer.compose
- Reihenfolge: Validator -> Config kopieren -> ProfileStore/PlayerSession -> Fachmodule -> Monetization/Analytics
  -> RemoteGateway (register, seal) -> optional StateSync, wenn `services.sendState` gesetzt.
- Remotes fest: `collect()`, `sell()`, `buyUpgrade(dimension)`, `unlockZone(zoneId)`; Rate Limits aus
  `config.remotes`. Neue Remote nur mit Auftrag, Schema, Rate Limit und Tests.
- Analytics-Kopplung über Ereignisse der Module (onCollected, onSold, onUpgraded, onUnlocked, onPurchase).

## StateSync (`core/src/server/StateSync.luau`)
- `markDirty(ctx)` nach Join, erfolgreichem dispatch, Refill mit neuen Items, gewährtem Kauf, Pass-Änderung.
- `flush()` sendet je Spieler höchstens einen Schnappschuss pro `minIntervalSeconds`; Fehler -> bleibt vorgemerkt.
- Schnappschuss nur mit Lesezugriffen erzeugt; Felder siehe Kopfkommentar. Nichts aufnehmen, was andere
  Spieler, Preise, Produkt-/Pass-IDs, PurchaseIds oder Funnel betrifft.
- Client-Seite: `core/client/ClientState.luau` übernimmt nur streng steigende `seq`.
