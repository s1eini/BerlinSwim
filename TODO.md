# TODO

## Scraper / Hosting
- [ ] **Geplante Scrape-Läufe prüfen.** Der GitHub-Zeitplan (`cron: "7-59/20 4-22 * * *"`) hat am 23.11.2026 trotz aktivem Workflow nicht ausgelöst. Nur Push- und manuelle Läufe kamen durch. Am 23.11. gegen 16:40 wurde der Workflow einmal deaktiviert und wieder aktiviert, um den Zeitplan neu anzumelden.
  - Prüfen: `gh run list --workflow scrape.yml` – erscheinen Läufe mit Event `schedule`?
  - Stand 23.11. ~19:15: weiterhin **kein** `schedule`-Lauf (seit 13:58 nur Push/manuell).
  - Falls weiterhin nichts kommt: externen Auslöser einrichten (z. B. cron-job.org, alle 20 min).
    - Er ruft `POST https://api.github.com/repos/s1eini/BerlinSwim/actions/workflows/scrape.yml/dispatches` mit `{"ref":"main"}` auf.
    - Dazu braucht es ein Fine-grained Token, das nur auf dieses Repo zugreift und nur die Berechtigung „Actions: Read and write“ hat.
- [ ] Node-20-Warnung von `actions/upload-pages-artifact@v4` beobachten und auf die nächste Major-Version anheben, sobald es eine gibt.

## App
- [ ] TestFlight: App in App Store Connect anlegen (Bundle-ID `de.eatbl.BerlinSwim`), Product → Archive → Upload. Vor jedem weiteren Upload `CURRENT_PROJECT_VERSION` in `ios/project.yml` erhöhen und `xcodegen` laufen lassen.
- [ ] Für externe Tester: Datenschutz-Seite (z. B. auf GitHub Pages) und Kontakt-E-Mail.
- [ ] Vor breiterer Verteilung: Nutzungsbedingungen der Berliner Bäder-Betriebe zur Datennutzung prüfen bzw. nachfragen.
- [ ] Offene Ideen: im Widget bei „Nur Favoriten“ auch geschlossene Favoriten zeigen; „nur noch“ im Widget orange wie auf den Karten; Beckenname in der Wochenübersicht bei Bädern mit mehreren Becken (z. B. Seestraße); „50 m“ doppelt (Kopfzeile + Chip) im Widget.
