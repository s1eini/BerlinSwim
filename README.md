# BerlinSwim

Inoffizielle iOS-App (iOS 26, SwiftUI) + Widget: Welche Berliner Bäder haben **jetzt** öffentliches Schwimmen, sind von hier erreichbar und lassen noch genug Zeit fürs Training?

## Aufbau
- `scraper/` – Python (stdlib) liest berlinerbaeder.de aus → `pools.json` (Öffnungszeiten pro Bereich, Hinweise/Schließungen, Wassertemperatur, Ausstattung). Tests: `python3 -m unittest discover -s scraper/tests`
- `.github/workflows/scrape.yml` – scrapt alle 20 min und veröffentlicht auf GitHub Pages: <https://berlinswim.eatbl.de/pools.json>
- `ios/BadKit` – gemeinsame Modelle + Rechenlogik (`SwimPlanner`). Tests: `cd ios/BadKit && swift test`
- `ios/BerlinSwim`, `ios/BerlinSwimWidget` – App & Widget. Projekt erzeugen: `cd ios && xcodegen`

Daten: Berliner Bäder-Betriebe, ohne Gewähr.
