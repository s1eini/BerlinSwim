"""Pure parsing functions for berlinerbaeder.de HTML (stdlib only).

The site's HTML is not well-formed (stray </tr>, rows without <tr>), so we
tokenize with a regex and walk tokens sequentially instead of building a tree.
"""
from __future__ import annotations

import html
import re
from dataclasses import dataclass, field
from datetime import date

TOKEN_RE = re.compile(r"<!--.*?-->|<(/?)([a-zA-Z0-9]+)([^>]*)>|([^<]+)", re.S)
ATTR_RE = re.compile(r'([a-zA-Z_:\-]+)\s*=\s*"([^"]*)"')
TIME_RANGE_RE = re.compile(r"(\d{1,2}):(\d{2})\s*-\s*(\d{1,2}):(\d{2})")
DATE_RANGE_RE = re.compile(r"(\d{2})\.(\d{2})\.(\d{2})\s*-\s*(\d{2})\.(\d{2})\.(\d{2})")
WEEKDAYS = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]


@dataclass
class Tok:
    kind: str  # "open" | "close" | "text"
    name: str = ""
    attrs: dict = field(default_factory=dict)
    text: str = ""

    def cls(self) -> list[str]:
        return self.attrs.get("class", "").split()


def tokenize(s: str) -> list[Tok]:
    s = re.sub(r"<(script|style)\b.*?</\1>", " ", s, flags=re.S | re.I)
    out: list[Tok] = []
    for m in TOKEN_RE.finditer(s):
        if m.group(4) is not None:
            t = " ".join(html.unescape(m.group(4)).split())
            if t:
                out.append(Tok("text", text=t))
        elif m.group(2):
            attrs = {k: html.unescape(v) for k, v in ATTR_RE.findall(m.group(3) or "")}
            out.append(Tok("close" if m.group(1) else "open", m.group(2).lower(), attrs))
    return out


def text_between(toks: list[Tok], start: int, end: int) -> str:
    return " ".join(t.text for t in toks[start:end] if t.kind == "text")


def find_matching_close(toks: list[Tok], i: int) -> int:
    """Index of the close tag matching toks[i] (counting same-name nesting)."""
    name, depth = toks[i].name, 0
    for j in range(i, len(toks)):
        t = toks[j]
        if t.name == name:
            if t.kind == "open":
                depth += 1
            elif t.kind == "close":
                depth -= 1
                if depth == 0:
                    return j
    return len(toks)


def find_open(toks, cls: str | None = None, start: int = 0, end: int | None = None, name: str | None = None, id_: str | None = None):
    end = len(toks) if end is None else end
    for i in range(start, end):
        t = toks[i]
        if t.kind != "open":
            continue
        if name and t.name != name:
            continue
        if cls and cls not in t.cls():
            continue
        if id_ and t.attrs.get("id") != id_:
            continue
        return i
    return -1


def find_all_open(toks, cls: str, start: int = 0, end: int | None = None, name: str | None = None):
    end = len(toks) if end is None else end
    return [i for i in range(start, end)
            if toks[i].kind == "open" and cls in toks[i].cls() and (name is None or toks[i].name == name)]


# --------------------------------------------------------------------------- list page

MARKER_RE = re.compile(r"bathmapMarkerTemplate\[(\d+)\]\s*=\s*\{(.*?)\};", re.S)
MARKER_FIELD_RE = re.compile(r"(\w+):\s*'([^']*)'")


def parse_list_page(s: str) -> list[dict]:
    markers = {}
    for m in MARKER_RE.finditer(s):
        f = {k: html.unescape(v) for k, v in MARKER_FIELD_RE.findall(m.group(2))}
        markers[int(m.group(1))] = f

    toks = tokenize(s)
    pools = []
    for i in find_all_open(toks, "bathlist_item", name="div"):
        j = find_matching_close(toks, i)
        p: dict = {}
        k = find_open(toks, "type", i, j, name="span")
        if k >= 0:
            p["type"] = text_between(toks, k, find_matching_close(toks, k))
        k = find_open(toks, "list_title_link", i, j, name="a")
        if k >= 0:
            p["name"] = text_between(toks, k, find_matching_close(toks, k))
            p["url"] = toks[k].attrs.get("href", "")
        k = find_open(toks, "bathlist_item_contents_text_address", i, j)
        if k >= 0:
            p["address_line"] = text_between(toks, k, find_matching_close(toks, k))
        k = find_open(toks, "item_traffic", i, j)
        if k >= 0:
            p["id"] = int(toks[k].attrs.get("data-bath", "0"))
            p["bathtype"] = int(toks[k].attrs.get("data-bathtype", "0") or 0)
        k = find_open(toks, "bathlist_item_contents_occupancy", i, j)
        if k >= 0:
            p["list_status"] = text_between(toks, k, find_matching_close(toks, k))
        if not p.get("id"):
            continue
        mk = markers.get(p["id"], {})
        p["lat"] = float(mk["lat"]) if mk.get("lat") else None
        p["lon"] = float(mk["lon"]) if mk.get("lon") else None
        p["ticket_url"] = mk.get("ticketurl") or None
        p["closed_flag"] = mk.get("closed") == "1"
        p.update(split_address(p.get("address_line", "")))
        pools.append(p)
    return pools


def split_address(line: str) -> dict:
    # "Lipschitzallee 27-33, 12351 Berlin Neukölln"
    m = re.match(r"(.*?),\s*(\d{5})\s+Berlin\s*(.*)", line)
    if not m:
        return {"street": line, "zip": None, "district": None}
    return {"street": m.group(1).strip(), "zip": m.group(2), "district": m.group(3).strip() or None}


def list_page_count(s: str) -> int:
    nums = [int(n) for n in re.findall(r'href="/baeder/page/(\d+)/"', s)]
    return max(nums) if nums else 1


# --------------------------------------------------------------------------- detail page

def parse_detail_page(s: str) -> dict:
    toks = tokenize(s)
    d: dict = {"notices": [], "areas": [], "equipment": [], "accessibility": [], "extras": []}

    # Closed banner ("Das Bad ist geschlossen." + explanation)
    for i in find_all_open(toks, "facility_body_content_alert"):
        for txt in alert_items(toks, i):
            d["notices"].append({"text": txt, "severity": "closed" if "geschlossen" in txt.lower() else "info"})
    # Sub alerts ("Hinweise") – one notice per <div class="item">
    for i in find_all_open(toks, "facility_body_content_subalert"):
        for txt in alert_items(toks, i):
            d["notices"].append({"text": txt, "severity": classify_notice(txt)})

    i = find_open(toks, "facility_body_content_subtitle")
    if i >= 0:
        h = find_open(toks, None, i, name="h1")
        if h >= 0:
            d["title"] = text_between(toks, h, find_matching_close(toks, h))
            p = find_open(toks, None, h, name="p")
            if p >= 0 and p - h < 10:
                d["description"] = text_between(toks, p, find_matching_close(toks, p))

    # Equipment: h2#Badausstattung, then facility_equipment blocks; an h3 "Barrierefreiheit" switches target.
    eq = find_open(toks, None, id_="Badausstattung")
    if eq >= 0:
        stop = find_open(toks, None, eq + 1, name="h2")
        stop = len(toks) if stop < 0 else stop
        target = "equipment"
        k = eq + 1
        while k < stop:
            t = toks[k]
            if t.kind == "open" and t.name == "h3":
                hdr = text_between(toks, k, find_matching_close(toks, k)).lower()
                target = "accessibility" if "barriere" in hdr else "equipment"
            elif t.kind == "open" and "facility_equipment" in t.cls():
                end = find_matching_close(toks, k)
                for c in range(k + 1, end):
                    if toks[c].kind == "open" and toks[c].name == "div":
                        txt = text_between(toks, c, find_matching_close(toks, c))
                        if txt and txt not in d[target]:
                            d[target].append(txt)
                k = end
            elif t.kind == "open" and "facility_add" in t.cls():
                end = find_matching_close(toks, k)
                for c in range(k + 1, end):
                    if toks[c].kind == "open" and toks[c].name == "li":
                        txt = text_between(toks, c, find_matching_close(toks, c))
                        if txt:
                            d["extras"].append(txt)
                k = end
            k += 1

    m = re.search(r"Bad-Kategorie\s+(\d)", s)
    d["category"] = int(m.group(1)) if m else None

    plain = " ".join(t.text for t in toks if t.kind == "text")
    m = re.search(r"Einlass- und Kassenschluss:\s*(\d+)\s*Minuten", plain)
    d["entry_cutoff_min"] = int(m.group(1)) if m else None
    m = re.search(r"Badeschluss:\s*(\d+)\s*Minuten", plain)
    d["exit_before_close_min"] = int(m.group(1)) if m else None
    d["water_temps"] = find_water_temps(plain)
    m = re.search(r"Bus und Bahn\s+(.*?)\s+(?:#SOPOOL|Facebook)", plain)
    d["transit"] = m.group(1) if m else None

    d["areas"] = parse_opening_areas(toks)
    return d


def alert_items(toks: list[Tok], i: int) -> list[str]:
    """Texts of the <div class="item"> children of an alert block (or the whole block if it has none)."""
    end = find_matching_close(toks, i)
    items = [k for k in range(i + 1, end) if toks[k].kind == "open" and "item" in toks[k].cls()]
    texts = [text_between(toks, k, find_matching_close(toks, k)) for k in items] if items \
        else [text_between(toks, i, end)]
    return [t for t in texts if t]


def classify_notice(txt: str) -> str:
    low = txt.lower()
    if re.search(r"geschlossen|fällt\s+aus|entfällt|gesperrt|außer\s+betrieb|nicht\s+(?:geöffnet|nutzbar|verfügbar)", low):
        return "warning"
    return "info"


def find_water_temps(plain: str) -> list[dict]:
    """'Wassertemperatur Schwimmerbecken: 27,7°C, Nichtschwimmerbecken: 27,2°C' -> list."""
    m = re.search(r"Wassertemperatur\s+(.{0,250}?°\s*C)(?!\s*,)", plain)
    if not m:
        return []
    return [{"basin": b.strip(), "tempC": float(t.replace(",", "."))}
            for b, t in re.findall(r"([A-ZÄÖÜ][\wäöüß\- ]{1,40}?):\s*(\d{1,2}(?:,\d)?)\s*°\s*C", m.group(1))]


def parse_opening_areas(toks: list[Tok]) -> list[dict]:
    areas = []
    tabs = find_open(toks, None, id_="areatabs")
    names: dict[str, str] = {}
    if tabs >= 0:
        end = find_matching_close(toks, tabs)
        for k in range(tabs, end):
            t = toks[k]
            if t.kind == "open" and t.name == "button" and "area-btn" in t.cls():
                target = t.attrs.get("data-bs-target", "").lstrip("#")
                names[target] = text_between(toks, k, find_matching_close(toks, k))
    for area_id, area_name in names.items():
        a = find_open(toks, None, id_=area_id)
        if a < 0:
            continue
        a_end = find_matching_close(toks, a)
        tables, seen = [], set()
        for ti in find_all_open(toks, "openingtime", a, a_end, name="table"):
            tbl = parse_table(toks, ti, find_matching_close(toks, ti))
            key = (tbl["label"], tbl["from"], tbl["to"])
            if tbl and key not in seen:
                seen.add(key)
                tables.append(tbl)
        areas.append({"name": area_name, "tables": tables})
    return areas


def parse_table(toks: list[Tok], start: int, end: int) -> dict:
    cap = find_open(toks, None, start, end, name="caption")
    caption = text_between(toks, cap, find_matching_close(toks, cap)) if cap >= 0 else ""
    hidden = find_open(toks, "d-print-inline", cap, end, name="span") if cap >= 0 else -1
    area_prefix = text_between(toks, hidden, find_matching_close(toks, hidden)) if hidden >= 0 else ""
    label = caption[len(area_prefix):].strip() if area_prefix and caption.startswith(area_prefix) else caption
    m = DATE_RANGE_RE.search(label)
    frm = to = None
    if m:
        d1, m1, y1, d2, m2, y2 = map(int, m.groups())
        frm, to = date(2000 + y1, m1, d1).isoformat(), date(2000 + y2, m2, d2).isoformat()
        label = DATE_RANGE_RE.sub("", label).strip()

    days: dict[str, list | str] = {}
    current = None
    k = cap if cap >= 0 else start
    while k < end:
        t = toks[k]
        if t.kind == "open" and t.name == "th" and "day" in t.cls():
            txt = text_between(toks, k, find_matching_close(toks, k))
            current = txt if txt in WEEKDAYS else None
            if current:
                days.setdefault(current, [])
            k = find_matching_close(toks, k)
        elif t.kind == "open" and t.name == "td" and current:
            td_end = find_matching_close(toks, k)
            if "closed" in t.cls():
                days[current] = "closed"
            else:
                txt = " ".join(x.text for x in toks[k:td_end] if x.kind == "text" and x.text not in WEEKDAYS)
                rm = TIME_RANGE_RE.search(txt)
                if rm and isinstance(days[current], list):
                    h1, m1, h2, m2 = map(int, rm.groups())
                    kind = t.attrs.get("title", "").strip()
                    days[current].append({
                        "start": f"{h1:02d}:{m1:02d}", "end": f"{h2:02d}:{m2:02d}",
                        "label": kind, "kind": slot_kind(kind),
                    })
            k = td_end
        k += 1
    return {"label": label, "from": frm, "to": to, "special": "special" in toks[start].cls(), "days": days}


def slot_kind(label: str) -> str:
    """public | limited (reduced water area) | restricted (only some groups) | private."""
    low = label.lower()
    if not low or re.search(r"\bkein\b|geschlossen|reserviert", low):
        return "private"
    if low.strip() == "gemischt":  # sauna: mixed = open to everyone
        return "public"
    if "öffentl" in low:
        if "nur für" in low:
            return "restricted"
        if "eingeschränkt" in low:
            return "limited"
        return "public"
    if re.search(r"\bnur\b|vereins|schul|kursbetrieb", low):
        return "private"
    return "restricted"  # "Frauen", "Menschen mit Behinderung", sauna "gemischt", ...


def is_public(label: str) -> bool:
    return slot_kind(label) in ("public", "limited")
