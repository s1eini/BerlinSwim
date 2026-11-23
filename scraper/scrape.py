#!/usr/bin/env python3
"""Scrape berlinerbaeder.de and write a compact pools.json for the BerlinSwim app.

Usage:
    python3 scrape.py --out build/pools.json            # live
    python3 scrape.py --fixtures tests/fixtures --out x  # offline (only fixture pools)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
import urllib.request
from datetime import date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

sys.path.insert(0, str(Path(__file__).parent))
import bbparse  # noqa: E402

BASE = "https://www.berlinerbaeder.de"
TZ = ZoneInfo("Europe/Berlin")
USER_AGENT = "BerlinSwim-Scraper/1.0 (+https://github.com/s1eini/BerlinSwim)"
DAYS_AHEAD = 14
SCHEMA_VERSION = 1


class Fetcher:
    def __init__(self, delay: float = 0.5):
        self.delay = delay
        self._last = 0.0

    def get(self, path: str) -> str:
        wait = self.delay - (time.monotonic() - self._last)
        if wait > 0:
            time.sleep(wait)
        url = path if path.startswith("http") else BASE + path
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Language": "de"})
        for attempt in range(3):
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    self._last = time.monotonic()
                    return r.read().decode("utf-8", "replace")
            except Exception as e:  # noqa: BLE001
                if attempt == 2:
                    raise
                print(f"retry {url}: {e}", file=sys.stderr)
                time.sleep(2 * (attempt + 1))
        raise RuntimeError("unreachable")


# --------------------------------------------------------------------------- schedule resolution

def lane_length(equipment: list[str]) -> int | None:
    lens = [int(m.group(1)) for e in equipment if (m := re.match(r"(\d+)-m-Becken", e))]
    return max(lens) if lens else None


def area_kind(name: str) -> str:
    low = name.lower()
    if "sauna" in low:
        return "sauna"
    if re.search(r"therapie|lehrschwimm|kinder|plansch", low):
        return "therapy"
    return "swim"


PREFERRED_BASIN = re.compile(r"schwimmer|sport|50|25|mehrzweck|wettkampf", re.I)


def main_water_temp(temps: list[dict]) -> float | None:
    for t in temps:
        if PREFERRED_BASIN.search(t["basin"]) and not t["basin"].lower().startswith("nicht"):
            return t["tempC"]
    return temps[0]["tempC"] if temps else None


def pick_table(tables: list[dict], d: date) -> dict | None:
    """Most specific table whose date range contains d and that lists d's weekday."""
    wd = bbparse.WEEKDAYS[d.weekday()]
    best, best_span = None, None
    for t in tables:
        if not t["from"] or not t["to"]:
            continue
        f, to = date.fromisoformat(t["from"]), date.fromisoformat(t["to"])
        if not (f <= d <= to) or wd not in t["days"]:
            continue
        span = (to - f).days
        if best is None or span < best_span:
            best, best_span = t, span
    return best


def parse_closure_notice(text: str, today: date) -> list[date]:
    """Dates a warning notice says the pool is closed on (dd.mm.yyyy, optional 'bis' range)."""
    if "geschlossen" not in text.lower():
        return []
    dates = [date(int(y), int(m), int(d)) for d, m, y in re.findall(r"(\d{1,2})\.(\d{1,2})\.(\d{4})", text)]
    if re.search(r"\bbis\b", text) and len(dates) == 2 and dates[0] <= dates[1]:
        out, d = [], dates[0]
        while d <= dates[1]:
            out.append(d)
            d += timedelta(days=1)
        return out
    return dates


def to_dt(d: date, hhmm: str) -> datetime:
    h, m = map(int, hhmm.split(":"))
    if h == 24:
        return datetime(d.year, d.month, d.day, tzinfo=TZ) + timedelta(days=1, minutes=m)
    return datetime(d.year, d.month, d.day, h, m, tzinfo=TZ)


def resolve_area(area: dict, start: date, days: int, closed_dates: set[date]) -> list[dict]:
    slots = []
    for n in range(days):
        d = start + timedelta(days=n)
        if d in closed_dates:
            continue
        t = pick_table(area["tables"], d)
        if t is None:
            continue
        entries = t["days"][bbparse.WEEKDAYS[d.weekday()]]
        if entries == "closed":
            continue
        for e in entries:
            s, en = to_dt(d, e["start"]), to_dt(d, e["end"])
            if en <= s:
                en += timedelta(days=1)
            slots.append({
                "start": s.isoformat(timespec="seconds"),
                "end": en.isoformat(timespec="seconds"),
                "kind": e["kind"],
                "label": e["label"],
                "period": t["label"],
            })
    return slots


def build_pool(lst: dict, det: dict, traffic: dict, today: date) -> dict:
    closed_dates: set[date] = set()
    closures = []
    for n in det["notices"]:
        if n["severity"] == "warning":
            ds = parse_closure_notice(n["text"], today)
            closed_dates.update(ds)
            if ds:
                closures.append({"dates": [d.isoformat() for d in ds], "reason": n["text"]})

    pool_len = lane_length(det["equipment"])
    areas = []
    for a in det["areas"]:
        slots = resolve_area(a, today, DAYS_AHEAD, closed_dates)
        kind = area_kind(a["name"])
        areas.append({
            "name": a["name"],
            "kind": kind,
            "laneLength": pool_len if kind == "swim" else None,
            "slots": slots,
        })

    slug = lst["url"].strip("/").split("/")[-1]
    return {
        "id": lst["id"],
        "slug": slug,
        "name": lst["name"],
        "type": lst.get("type"),
        "district": lst.get("district"),
        "street": lst.get("street"),
        "zip": lst.get("zip"),
        "lat": lst.get("lat"),
        "lon": lst.get("lon"),
        "url": BASE + lst["url"],
        "ticketUrl": lst.get("ticket_url"),
        "closedNow": lst.get("closed_flag", False),
        "category": det.get("category"),
        "description": det.get("description"),
        "laneLength": pool_len,
        "equipment": det["equipment"],
        "accessibility": det["accessibility"],
        "extras": det["extras"],
        "transit": det.get("transit"),
        "waterTempC": main_water_temp(det["water_temps"]),
        "waterTemps": det["water_temps"],
        "traffic": traffic.get(lst["id"]),
        "notices": det["notices"],
        "closures": closures,
        "rules": {
            "entryCutoffMin": det.get("entry_cutoff_min") or 60,
            "exitBeforeCloseMin": det.get("exit_before_close_min") or 30,
        },
        "areas": areas,
    }


def parse_traffic(raw: str) -> dict[int, int]:
    try:
        rows = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    out = {}
    for r in rows:
        try:
            lvl = int(r.get("level", -1))
            if lvl >= 0:
                out[int(r["id"])] = lvl
        except (TypeError, ValueError, KeyError):
            continue
    return out


# --------------------------------------------------------------------------- main

def scrape_live(fetch: Fetcher) -> tuple[list[dict], dict[str, str], str]:
    first = fetch.get("/baeder/")
    pages = bbparse.list_page_count(first)
    listing = bbparse.parse_list_page(first)
    for p in range(2, pages + 1):
        listing += bbparse.parse_list_page(fetch.get(f"/baeder/page/{p}/"))
    details = {}
    for p in listing:
        details[p["url"]] = fetch.get(p["url"])
    try:
        traffic = fetch.get("/traffic/trafficdata.json")
    except Exception:  # noqa: BLE001
        traffic = "[]"
    return listing, details, traffic


def scrape_fixtures(folder: Path) -> tuple[list[dict], dict[str, str], str]:
    listing = []
    for f in sorted(folder.glob("list_page*.html")):
        listing += bbparse.parse_list_page(f.read_text())
    details = {}
    for p in listing:
        f = folder / f"detail_{p['url'].strip('/').split('/')[-1]}.html"
        if f.exists():
            details[p["url"]] = f.read_text()
    tf = folder / "traffic.json"
    return [p for p in listing if p["url"] in details], details, tf.read_text() if tf.exists() else "[]"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/pools.json")
    ap.add_argument("--fixtures", type=Path)
    ap.add_argument("--today", help="override date (YYYY-MM-DD), for tests")
    args = ap.parse_args()

    today = date.fromisoformat(args.today) if args.today else datetime.now(TZ).date()
    if args.fixtures:
        listing, details, traffic_raw = scrape_fixtures(args.fixtures)
    else:
        listing, details, traffic_raw = scrape_live(Fetcher())

    seen, pools, errors = set(), [], []
    traffic = parse_traffic(traffic_raw)
    for lst in listing:
        if lst["id"] in seen:
            continue
        seen.add(lst["id"])
        try:
            pools.append(build_pool(lst, bbparse.parse_detail_page(details[lst["url"]]), traffic, today))
        except Exception as e:  # noqa: BLE001
            errors.append(f"{lst.get('name')}: {e!r}")

    if not args.fixtures and len(pools) < 40:
        print(f"Only {len(pools)} pools parsed - refusing to publish. Errors: {errors}", file=sys.stderr)
        return 1

    out = {
        "schemaVersion": SCHEMA_VERSION,
        "generatedAt": datetime.now(TZ).isoformat(timespec="seconds"),
        "source": BASE + "/baeder/",
        "pools": sorted(pools, key=lambda p: p["name"]),
    }
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text(json.dumps(out, ensure_ascii=False, separators=(",", ":")))
    print(f"wrote {len(pools)} pools to {args.out}; {len(errors)} errors", file=sys.stderr)
    for e in errors:
        print("  " + e, file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
