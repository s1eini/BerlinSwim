"""Run: python3 -m unittest discover -s scraper/tests"""
import json
import sys
import unittest
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FIX = ROOT / "tests" / "fixtures"
sys.path.insert(0, str(ROOT))

import bbparse  # noqa: E402
import scrape  # noqa: E402


def detail(slug: str) -> dict:
    return bbparse.parse_detail_page((FIX / f"detail_{slug}.html").read_text())


class ListPageTests(unittest.TestCase):
    def test_list_page_has_cards_with_coordinates(self):
        pools = bbparse.parse_list_page((FIX / "list_page1.html").read_text())
        self.assertEqual(len(pools), 10)
        see = next(p for p in pools if p["id"] == 9)
        self.assertEqual(see["name"], "Kombibad Seestraße - Hallenbad")
        self.assertEqual(see["district"], "Mitte")
        self.assertAlmostEqual(see["lat"], 52.557234)
        self.assertFalse(see["closed_flag"])  # list says open although detail says Teamtag
        wannsee = next(p for p in pools if p["id"] == 35)
        self.assertTrue(wannsee["closed_flag"])
        self.assertEqual(wannsee["type"], "Strandbad")

    def test_page_count(self):
        self.assertEqual(bbparse.list_page_count((FIX / "list_page1.html").read_text()), 7)


class DetailPageTests(unittest.TestCase):
    def test_seestrasse_areas_and_teamtag(self):
        d = detail("seestrasse")
        self.assertEqual([a["name"] for a in d["areas"]], ["Hallenbad", "Traglufthalle", "Therapiebecken"])
        halle = d["areas"][0]
        team = next(t for t in halle["tables"] if t["label"] == "Teamtag")
        self.assertEqual(team["from"], "2026-11-23")
        self.assertEqual(team["days"]["Montag"], "closed")
        regular = next(t for t in halle["tables"] if t["label"] == "Öffnungszeiten")
        tue = regular["days"]["Dienstag"]
        self.assertEqual([(s["start"], s["end"], s["kind"]) for s in tue],
                         [("08:00", "16:00", "private"), ("16:00", "22:00", "public")])
        self.assertEqual(d["entry_cutoff_min"], 60)
        self.assertEqual(d["exit_before_close_min"], 30)
        self.assertIn("50-m-Becken", d["equipment"])
        self.assertIn("Wasserlift", d["accessibility"])
        self.assertEqual(d["category"], 2)
        self.assertTrue(any(n["severity"] == "warning" for n in d["notices"]))

    def test_summer_pool_closed_banner(self):
        d = detail("strandbad-wannsee")
        self.assertEqual(d["areas"], [])
        self.assertEqual(d["notices"][0]["severity"], "closed")
        self.assertEqual(len(d["notices"]), 3)


    def test_one_notice_per_item(self):
        html = ('<div class="facility_body_content_subalert"><div class="item"><div class="msg"> Film am Dienstag. '
                '</div></div><div class="item"><div class="msg">Das Solebecken ist geschlossen.</div></div></div>')
        d = bbparse.parse_detail_page(html)
        self.assertEqual([n["text"] for n in d["notices"]], ["Film am Dienstag.", "Das Solebecken ist geschlossen."])
        self.assertEqual([n["severity"] for n in d["notices"]], ["info", "warning"])


    def test_prices_with_groups(self):
        html = (
            '<div class="facility_prices_content">'
            '<div class="facility_prices_content_intro"><p>Dieses Bad gehört zur Bad-Kategorie 1.</p></div>'
            '<div class="facility_prices_content_intro"><p><strong>Kinder unter 5 frei.</strong></p></div>'
            '<div class="table"><div class="table-header-group"><div class="table-row"><div class="table-head"> Badetarif </div></div></div>'
            '<div class="table-body-group"><div class="table-row"><div class="table-cell"><span class="mobilehead">Badetarif:</span>'
            ' 90-Minuten-Ticket <span class="subtitle">Nachzahlung möglich.</span></div>'
            '<div class="table-cell price"><span class="mobilelabel">Preis</span> 6,00 € </div>'
            '<div class="table-cell price"><span class="mobilelabel">Ermäßigt</span> - </div></div></div></div>'
            '<div class="table"><div class="table-header-group"><div class="table-row"><div class="table-head"> Saunatarif </div></div></div>'
            '<div class="table-body-group"><div class="table-row"><div class="table-cell"> Tageskarte <span class="subtitle"></span></div>'
            '<div class="table-cell price"> 23,00 € </div><div class="table-cell price"> 19,00 € </div></div></div></div>'
            '<div class="facility_prices_content_footer"><ul><li>Kinder von 5 bis 14</li></ul></div>'
            '</div>')
        d = bbparse.parse_detail_page(html)
        self.assertEqual(d["prices"][0], {"group": "Badetarif", "title": "90-Minuten-Ticket",
                                          "note": "Nachzahlung möglich.", "price": "6,00 €", "reduced": None})
        self.assertEqual((d["prices"][1]["group"], d["prices"][1]["title"], d["prices"][1]["reduced"]),
                         ("Saunatarif", "Tageskarte", "19,00 €"))
        self.assertEqual(d["price_notes"], ["Kinder unter 5 frei."])
        self.assertEqual(d["reduced_for"], ["Kinder von 5 bis 14"])


class ClassificationTests(unittest.TestCase):
    def test_sauna_mixed_is_public(self):
        self.assertEqual(bbparse.slot_kind("gemischt"), "public")
        self.assertEqual(bbparse.slot_kind("Frauen"), "restricted")

    def test_slot_kinds(self):
        k = bbparse.slot_kind
        self.assertEqual(k("öffentl. Schwimmen"), "public")
        self.assertEqual(k("öffentl. Schwimmen mit eingeschränkter Wasserfläche"), "limited")
        self.assertEqual(k("nur Schul-, Vereins-, Kursbetrieb"), "private")
        self.assertEqual(k("kein öffentl. Schwimmen aufgrund eines Wettkampfs"), "private")
        self.assertEqual(k("öffentl. Schwimmen nur für Menschen mit Behinderung, Senioren"), "restricted")
        self.assertEqual(k("Frauenschwimmen"), "restricted")

    def test_water_temps(self):
        t = bbparse.find_water_temps(
            "Wassertemperatur Lehrschwimmbecken: 27,9°C, Mehrzweckbecken: 28,7°C, Sprungbecken: 28,2°C Die Temperaturen")
        self.assertEqual([x["basin"] for x in t], ["Lehrschwimmbecken", "Mehrzweckbecken", "Sprungbecken"])
        self.assertEqual(scrape.main_water_temp(t), 28.7)

    def test_closure_notice_dates(self):
        txt = "ist das Bad am Montag, den 23.11.2026 aufgrund einer Team-Weiterbildung geschlossen."
        self.assertEqual(scrape.parse_closure_notice(txt, date(2026, 11, 23)), [date(2026, 11, 23)])
        rng = "Das Bad ist vom 01.12.2026 bis 03.12.2026 geschlossen."
        self.assertEqual(len(scrape.parse_closure_notice(rng, date(2026, 11, 23))), 3)
        self.assertEqual(scrape.parse_closure_notice("Nur kalte Duschen am 01.12.2026", date(2026, 11, 23)), [])


class ResolutionTests(unittest.TestCase):
    def test_teamtag_overrides_regular_and_slots_resolve(self):
        d = detail("seestrasse")
        lst = {"id": 9, "name": "Kombibad Seestraße - Hallenbad", "url": "/baeder/detail/kombibad-seestrasse-hallenbad/"}
        pool = scrape.build_pool(lst, d, {}, date(2026, 11, 23))
        halle = pool["areas"][0]
        self.assertEqual(halle["kind"], "swim")
        self.assertEqual(halle["laneLength"], 50)
        self.assertFalse(any(s["start"].startswith("2026-11-23") for s in halle["slots"]))
        tue = [s for s in halle["slots"] if s["start"].startswith("2026-11-24")]
        self.assertEqual(tue[-1]["start"], "2026-11-24T16:00:00+01:00")
        self.assertEqual(tue[-1]["kind"], "public")
        self.assertEqual(pool["areas"][2]["kind"], "therapy")
        json.dumps(pool)  # serializable

    def test_christmas_table_wins_over_regular(self):
        d = detail("seestrasse")
        tables = d["areas"][0]["tables"]
        self.assertEqual(scrape.pick_table(tables, date(2026, 12, 23))["label"], "1. Woche Weihnachtsferien")
        self.assertEqual(scrape.pick_table(tables, date(2026, 12, 1))["label"], "Öffnungszeiten")


if __name__ == "__main__":
    unittest.main()
