# Junkyard Magnet – Stilvorgabe (verbindlich)

## Look
- Stilisiert, Low-Poly, freundlich und bunt. Kein Fotorealismus, kein Düster-Look.
- Klare Silhouetten, die auf dem Handy aus 10 m erkennbar sind: wenige große Formen, deutliche Vorsprünge (Zähne, Flansche, Reifen, Nieten), keine feinen Details unter etwa 0,1 Studs.
- Flache Flächen (Flat Shading), kleine Fasen nur dort, wo Metall Glanzlichter fangen soll.
- Keine Texte, Logos oder Marken, keine echten Fahrzeugmarken oder erkennbaren Markenprodukte. Keine Unions.

## Palette (16 Farben, verbindlich)
Die Werte stehen identisch in `scripts/jm_common.py` (`PALETTE`). Erweitert um zwei Farben (Rückmeldung Björn): dunkle Reifen und Grau-/Metalltöne für gemischte Schrotthaufen. Später ergänzt: Holzbraun für Baumstämme und Holzmasten (vorher rust_dark, wirkte rot) und Dunkelgrün als Wrack-Lackfarbe.

- rust_dark `#8A3B1E`: Rost dunkel, Schmutzhügel, Rost-Akzente
- rust_orange `#E0702E`: Rost hell (rusty, Hauptfarbe)
- chrome_light `#DCE6F0`: Chrom hell, Magnet-Polschuhe, Himmel am Horizont (Render)
- chrome_dark `#7D8B99`: Chrom-Akzent, Rahmen, Griff
- gold `#FFC21A`: Gold (gold, Hauptfarbe)
- gold_deep `#C9800C`: Gold-Akzent
- neon_cyan `#2BF5E3`: Neon (neon, Hauptfarbe, leuchtend)
- neon_pink `#FF45D6`: Neon-Akzent (leuchtend)
- magnet_red `#E8322F`: Magnetkörper
- steel_blue `#3F72A8`: Container, Zenit des Himmels (Render)
- olive_green `#7A9E3E`: Farbtupfer (Reifen), Vegetation
- sand `#D9B98A`: Boden
- tire_black `#2B2B2E`: Reifen, Gummi
- metal_gray `#6E7781`: Grautöne in Schrotthaufen, lackierte graue Teile
- bark_brown `#6B4A2F`: Baumstämme, Holzmasten
- bottle_green `#2F5D3A`: Wrack-Lack dunkelgrün

Wracks bekommen im Spiel wechselnde Lackfarben aus der Palette (magnet_red, steel_blue, chrome_light, gold, rust_orange, bottle_green, olive_green); das Modell bleibt eines.

## Seltenheiten
Jede Seltenheit ist eine Materialvariante derselben Form, mit Haupt- und Akzentmaterial. Die Werte sind Farbe, metallic, roughness und Emission.

- rusty (gewöhnlich): rust_orange 0.2/0.85, Akzent rust_dark 0.1/0.9
- chrome (selten): chrome_light 1.0/0.12, Akzent chrome_dark 0.8/0.35
- gold (episch): gold 1.0/0.25, Akzent gold_deep 1.0/0.35
- neon (legendär): neon_cyan mit Emission 1.4, Akzent neon_pink mit Emission 3.5

In Roblox entspricht neon dem Material Neon bzw. einer SurfaceAppearance mit Emission. Wie der Importer die Materialwerte übernimmt, ist noch zu prüfen.

## Maße, Drehpunkt, Ausrichtung
- 1 Blender-Einheit = 1 Stud. Die Szene setzt `scale_length = 0.28`, also 1 Stud = 0.28 m. Der FBX-Export schreibt damit echte Meter, und der Roblox-Importer rechnet sie zurück in Studs. In Studio zu bestätigen.
- Items: 1 bis 3 Studs, zum Beispiel Blechplatte 2.4 x 1.8 x 0.5.
- Magnet: etwa 2 Studs hoch, passend zur Avatarhand.
- Kulisse: 8 bis 30 Studs; Container 20 x 8 x 8.5, Schrotthaufen etwa 16 x 13 x 9.
- Drehpunkt Mitte unten.
- Vorderseite zeigt in Blender nach -Y. Mit dem Standard-FBX-Export (Forward -Z, Up Y) wird daraus Roblox +Z.

## Dreiecksbudget je Objekt
- Items: höchstens 1.500
- Magnet: höchstens 3.000
- Kulisse: höchstens 8.000

`jm_common.report` prüft das Budget bei jedem Export und bricht bei Überschreitung ab.

## Reproduzierbarkeit
- Jedes Objekt entsteht vollständig aus seinem Skript in `scripts/`; zufällige Anteile sind fest geseedet.
- Export nach `export/` als .fbx.
- Renders entstehen mit `scripts/jm_render.py` nach `build/art/renders/`.
- .blend-Dateien gehören nicht ins Repo; Ablage ist `build/art/`.

## Store-Bilder
- Entwürfe in `store/`: Vorschaubild 1920 x 1080 und Icon 512 x 512, je Variante A (Seitenansicht, Figur vorne links, Kran dahinter) und B (Dreiviertel-Frontansicht). Ohne Text und Logos.
- Björns Wahl: Variante A ist der aktuelle Favorit. Status: Entwurf, noch nicht in der Experience gesetzt.
- Entstanden als Studio-Aufnahme aus der echten Karte (1736 x 793, auf 1920 x 1080 hochgerechnet).
- Spätere Verbesserung: Magnet als echtes Modell in der Hand, Figur mit Schutzhelm und Arbeitsjacke, schärferer Boden.
