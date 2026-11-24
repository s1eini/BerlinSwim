# TODO

## Scraper / Hosting
- [x] **Geplante Scrape-Läufe prüfen.** → Seit 24.11. ~10:18 startet ein externer Cron (cron-job.org, alle 20 min) den Workflow per `workflow_dispatch`. GitHubs eigener Zeitplan lief in 20 h nur einmal, Stunden zu spät. Der GitHub-Zeitplan (`cron: "7-59/20 4-22 * * *"`) hat am 23.11.2026 trotz aktivem Workflow nicht ausgelöst. Nur Push- und manuelle Läufe kamen durch. Am 23.11. gegen 16:40 wurde der Workflow einmal deaktiviert und wieder aktiviert, um den Zeitplan neu anzumelden.
  - Prüfen: `gh run list --workflow scrape.yml` – erscheinen Läufe mit Event `schedule`?
  - Stand 23.11. ~19:15: weiterhin **kein** `schedule`-Lauf (seit 13:58 nur Push/manuell).
  - Falls weiterhin nichts kommt: externen Auslöser einrichten (z. B. cron-job.org, alle 20 min).
    - Er ruft `POST https://api.github.com/repos/s1eini/BerlinSwim/actions/workflows/scrape.yml/dispatches` mit `{"ref":"main"}` auf.
    - Dazu braucht es ein Fine-grained Token, das nur auf dieses Repo zugreift und nur die Berechtigung „Actions: Read and write“ hat.
- [ ] **Um den 27./28.11. prüfen:** Löst GitHubs `schedule` (als Fallback behalten) weiterhin nur vereinzelt aus? `gh run list --workflow scrape.yml` → Läufe mit Event `schedule` zählen. Wenn ja, den Fallback seltener laufen lassen (z. B. stündlich), damit er bei Ausfall von cron-job.org reicht, ohne Läufe zu verdoppeln.
- [ ] Node-20-Warnung von `actions/upload-pages-artifact@v4` beobachten und auf die nächste Major-Version anheben, sobald es eine gibt.

## App
- [ ] TestFlight: App in App Store Connect anlegen (Bundle-ID `de.eatbl.BerlinSwim`), Product → Archive → Upload. Vor jedem weiteren Upload `ios/scripts/bump-build.sh` ausführen (Build +1, `xcodegen` läuft mit; mit Argument z. B. `1.1.0` auch neue Version). Stand: 1.0.0 (2), in App Store Connect zuletzt 1.0.0 (1.1).
- [ ] Für externe Tester: Datenschutz-Seite (z. B. auf GitHub Pages) und Kontakt-E-Mail.
- [ ] Vor breiterer Verteilung: Nutzungsbedingungen der Berliner Bäder-Betriebe zur Datennutzung prüfen bzw. nachfragen.
- [ ] Offene Ideen: im Widget bei „Nur Favoriten“ auch geschlossene Favoriten zeigen; „nur noch“ im Widget orange wie auf den Karten; Beckenname in der Wochenübersicht bei Bädern mit mehreren Becken (z. B. Seestraße); „50 m“ doppelt (Kopfzeile + Chip) im Widget.
