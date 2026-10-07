---
name: factory-standards
description: Fabrik-Standards für Core, Kit und Games. Verwenden, wenn eine Game-Config, das Config-Schema, der Validator oder der Economy-Simulator geändert wird, ein Kit-Modul (kit/src) entsteht, ein neues Game unter games/ angelegt oder das Testbed angepasst wird, sowie bei Fragen zu Theme-Neutralität, Grenzcheck, UI-Tokens und Mobile-Bedienung.
---

# Fabrik-Standards

## Grenzcheck (`tools/core_boundary.py`)
- Prüft `core/src`, `core/client`, `kit/src` auf Theme-Begriffe (junkyard, magnet, scrap, schrott, treasure,
  deepsea, deep_sea; ganze Wörter inkl. camelCase-Grenzen) und `rbxassetid` überall. Fund = Exit 1.
- Theme, Texte, Assets und Welt gehören ins Game (`games/<id>/`), nie in Core oder Kit.
- Neue verbotene Begriffe nur mit Auftrag ergänzen; der Negativtest muss weiter einen Treffer liefern.

## Config-Schema, Validator, Simulator
- Schema: `core/src/server/Config/Schema.luau` (game, items, zones, upgrades, collect, sell, products, passes,
  remotes, texts, sim).
- `Validator.validate(config)` sammelt alle Fehler (wirft nie) mit Pfad und Code (MISSING_FIELD, WRONG_TYPE,
  INVALID_ID, COSTS_NOT_INCREASING, UNREACHABLE_ZONE, MISSING_TEXT, MISSING_REMOTE, ...). Er prüft alles, was
  Konstruktoren per assert prüfen würden: eine gültige Config darf in `GameServer.compose` nie einen assert
  auslösen. Neue Config-Felder immer zuerst in Schema + Validator + `core/tests/ConfigValidatorSpec.luau`.
- `Simulator` (`core/src/server/Config/Simulator.luau`) spielt deterministisch einen Spieler ohne Käufe und
  meldet Minuten bis erstem Verkauf, erstem Upgrade und jeder Zone. Grenzminuten (Fair-Play) sind Parameter von
  `check`, keine Konstanten im Core. Simulator-Report gehört in den Bericht jeder Config-Änderung.
- Preise in Robux, Produkt- und Pass-IDs: Platzhalter im Repo; echte Werte sind ein manuelles Gate.

## Kit-Regeln (`kit/src` -> `ReplicatedStorage.FactoryKit`)
- Jedes Kit-Teil trennt reine Logik (`*Model`, kopflos testbar, keine Instanzen) von dünner Darstellung
  (`*View`, baut Instanzen, ruft nur Intents auf). Beispiele: `HudModel`/`HudView`, `InputModel`/`InputView`,
  `OnboardingModel`/`OnboardingView`, `FeedbackModel`/`FeedbackView`, `ItemView`, Textersetzung in `Text`.
- Kit requirt nie `core/src`; nur `core/client` und eigene Module.
- Keine Spielentscheidungen im Kit; "leistbar"/"freischaltbar" nur für die Anzeige.
- Farben, Schrift, Abstände kommen als `uiTokens` aus dem Game; Formen/Farben der Items als `assetStyles`;
  Onboarding-Schritte als Daten. Keine Asset-IDs, keine Unions.
- Tests in `core/tests/KitSpec.luau` (Model-Logik und View in Test-Container mit Fake-Intents).

## Mobile zuerst
- Touch muss alles können: große Buttons (`MIN_TOUCH_SIZE` in `kit/src/HudView.luau`, begründet im Kopf),
  `GuiButton.Activated` für Maus, Touch und Gamepad. Tastatur E/Q und Gamepad ButtonX/ButtonY auf dieselben
  Absichten (`kit/src/InputModel.luau`).
- Layout auf kleinen Hochformat-Viewports prüfen (z. B. 456 x 784 im Studio-Spieltest); kein Element darf
  Chat, andere Buttons oder den Onboarding-Hinweis verdecken.

## Testbed als Referenz-Game (`games/testbed`)
- Theme-neutral: graue Flächen, einfache Formen, Namen wie `zone_a`, `item_small`; deutsche Texte in
  `config.texts`. Jedes neue Game folgt derselben Struktur:
  `shared/Config.luau` (config, assetStyles, uiTokens, onboardingSteps), `server/World.luau` (Welt-Konvention aus
  `core/src/server/Engine/WorldAdapter.luau`: `Workspace.FactoryWorld.Zones.<zoneId>`, `.SellAreas.*`),
  `server/Main.server.luau` (World.build + ServerRuntime.start), `client/Main.client.luau` (ClientState, Intents,
  Kit-Views). Dazu eine eigene `<game>.project.json` ohne Tests und ein Eintrag in `tools/spike/test_projects.py`.
- Neue Engine-Fähigkeiten zuerst im Testbed nachweisen, dann in Games nutzen.

## Theme-Neutralität
- Core und Kit kennen nur abstrakte Begriffe (item, zone, upgrade, coins, perk, role). Theme entsteht allein
  über Config-Texte, assetStyles, uiTokens und die Welt des Games.
- Generierte oder Creator-Store-Assets nur im Game und erst nach Björns Freigabe dauerhaft.
