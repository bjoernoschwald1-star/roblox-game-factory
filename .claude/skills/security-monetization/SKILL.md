---
name: security-monetization
description: Sicherheits- und Kaufregeln der Factory. Verwenden, wenn Remotes, RemoteGateway-Schemata oder Rate Limits, Client-Absichten, Developer Products, ProcessReceipt, Game Passes, Perks oder der Client-Schnappschuss geändert oder geprüft werden, sowie bei jedem Review auf Exploits.
---

# Sicherheit und Monetarisierung

## RemoteGateway (`core/src/server/RemoteGateway.luau`)
- Einziger Eingang für Client-Anfragen. `register(name, { args, rateLimit, handler })`, dann `seal()`;
  danach keine Registrierung mehr. Kein anderes Modul hört auf `OnServerEvent`; `ServerRuntime` leitet nur an
  `game:dispatch` weiter.
- Prüfreihenfolge in `dispatch`: `UNKNOWN_REMOTE` -> Argumentanzahl `BAD_ARGS` -> Schema `BAD_ARGS` ->
  `RATE_LIMITED` -> Handler wirft `HANDLER_ERROR`. Jede Ablehnung zählt pro Spieler (`rejectedCount`) und geht
  an `onRejected`; der Client bekommt nie eine Antwort.
- ArgSpec-Typen: `string` (maxLength, oneOf), `number` (min, max, integer; NaN/inf abgelehnt), `boolean`,
  `vector3` (endlich, maxMagnitude), `id` (isKnown). IDs immer gegen die Config prüfen.
- Rate Limits pro Spieler und Remote aus `config.remotes` (Testbed: `games/testbed/shared/Config.luau`).
- Nur RemoteEvents, keine RemoteFunctions (`core/src/server/Engine/RemoteBinder.luau`).

## Client
- `core/client/Intents.luau` sendet nur Absichten ohne Werte; die Client-Drossel ist Komfort, nicht Schutz.
- Kit-Logik (z. B. `kit/src/HudModel.luau` "affordable") dient nur der Anzeige; der Server entscheidet.

## Exploit-Prüfliste (bei jedem Review abhaken)
1. Gefälschte Argumente: zusätzliche Parameter (Preis, Menge, Position), falsche Typen, NaN/inf, riesige Strings,
   unbekannte IDs -> müssen `BAD_ARGS` ergeben, Handler nicht aufgerufen.
2. Remote-Flut: mehr als `max` Aufrufe im Fenster -> `RATE_LIMITED`; Limits pro Spieler und Remote getrennt.
3. Teleport-/Reichweiten-Betrug: Position nur serverseitig (`services.getPosition`), Reichweite mit
   `rangeTolerance`; `collect` hat ein eigenes Item-Limit (`config.collect.rateLimit`).
4. Fremde Items oder Zonen: nur eigene Items, nur freigeschaltete Zonen einsammeln.
5. Verkaufen außerhalb der Verkaufsfläche: `canSell` prüft serverseitig das Volumen (`WorldAdapter`).
6. Doppelkauf/Replay: PurchaseId im gespeicherten Profil; gleiche Quittung -> keine zweite Gutschrift, auch
   nach Serverwechsel (Session-Lock).
7. Reward bei "Prompt geschlossen" oder aus Client-Ereignis: verboten, nur `processReceipt`.
8. Pass-Besitz aus Client-Angabe: verboten; Besitz nur über `ownsPass`, nach Kaufabschluss serverseitig geprüft.
9. Negative oder nicht ganzzahlige Beträge, Überlauf bei Coins/Kosten: Economy und Validator lehnen ab.
10. Datenleck im Schnappschuss: keine anderen Spieler, Preise, Produkt-/Pass-IDs, PurchaseIds, Funnel.
11. Analytics: Feld `price` verboten, feste Event-Namen, keine Client-Werte als Preis.
12. Beschädigte Profilwerte: `CORRUPT_VALUE`, nichts überschreiben.

## ProcessReceipt (`core/src/server/Monetization.luau`)
1. Ungültige Quittung oder unbekannte ProductId -> warn, `NotProcessedYet`.
2. Profil nicht geladen, `purchases`/`perks` beschädigt -> `NotProcessedYet`, nichts geändert.
3. PurchaseId schon gespeichert -> `PurchaseGranted` ohne erneute Vergabe.
4. Rewards anwenden (Coins über `economy:credit` mit Grund `purchase`, Perks ins Set), PurchaseId vorne
   einfügen (höchstens `maxRemembered`), dann `session:save(ctx)`.
5. Speichern ok -> `onPurchase` in pcall, `PurchaseGranted`.
6. Speichern scheitert -> genau diese Änderungen zurückbauen (Coins gegenbuchen, bei zu wenig Guthaben auf 0 +
   warn; neue Perks entfernen; PurchaseId entfernen), `NotProcessedYet`. Grund: Roblox liefert erneut; ein
   nicht gespeicherter Kauf darf nicht per Autosave still festgeschrieben werden.
7. Scheitert ein Reward unterwegs -> bereits angewandte Rewards zurückbauen, `NotProcessedYet`.
- Tests dazu: `core/tests/MonetizationSpec.luau` (failUpdates, failUpdatesAfterWrite, Serverwechsel, LOCK_LOST).
- Reward-Typen nur `coins` und `perk`; Bündel (VIP) sind Listen in der Config, kein Sonderfall im Code.
- Preise setzt Björn auf Roblox (manuelles Gate); Config kennt nur Produkt-IDs und Rollen.

## Game Passes
- Wirken ausschließlich als Modifier-Quelle (`modifierSource`), lesen nur den Cache, yielden nie.
- `refreshPasses` beim Join und nach Kaufabschluss (ownsPass in pcall; Fehler = nicht besessen, später neu).
- Nie gespeicherte Werte verändern; Pass-Effekt darf nach Neuladen nicht im Profil stehen.

## Schnappschuss-Grenzen (`core/src/server/StateSync.luau`)
- Nur eigener Zustand, nur Anzeige; nichts, was der Client zurücksenden könnte, um einen Wert zu setzen.
