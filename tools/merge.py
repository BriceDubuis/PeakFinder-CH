"""Merge the summit lists, cross-check them, and flag bad rows.

Usage: python3 -I merge.py <raw_dir> <out_dir>
"""
import csv, math, os, re, sys, json, unicodedata
from collections import defaultdict

raw, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)

RANGE_ALIASES = {
    "schwyzer alps": "Schwyz Alps", "schwyz alps": "Schwyz Alps",
    "alpstein": "Appenzell Alps", "vaudw alps": "Vaud Alps",
    "fribourg alps": "Fribourg Prealps", "swiss prealps": None,
    "adula alps": "Lepontine Alps", "ticino alps": "Lepontine Alps",
    "saint-gotthard massif": "Lepontine Alps", "jura": "Jura Mountains",
    "sesvenna alps": "Sesvenna Range", "alps": None, "": None,
}

def norm_range(r):
    k = (r or "").strip().lower()
    return RANGE_ALIASES.get(k, (r or "").strip()) if k in RANGE_ALIASES else r.strip()

def km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    d = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(d))

def base(name):
    n = re.sub(r"\(.*?\)", "", name)
    n = n.split("/")[0]
    n = unicodedata.normalize("NFKD", n).encode("ascii", "ignore").decode().lower()
    return re.sub(r"[^a-z]", "", n)

rows = []
for fn in sorted(os.listdir(raw)):
    src_default = {"valais.csv": "VS", "bern.csv": "BE", "graubunden.csv": "GR"}.get(fn)
    with open(os.path.join(raw, fn), encoding="utf-8") as f:
        for r in csv.DictReader(f, delimiter=";"):
            try:
                lat, lon = float(r["lat"]), float(r["lon"])
            except (TypeError, ValueError):
                print("NO COORDS:", fn, r["name"]); continue
            rows.append(dict(name=r["name"].strip(), h=round(float(r["height_m"])),
                             p=int(float(r["prominence_m"] or 0)), lat=lat, lon=lon,
                             rng=norm_range(r["range"]), src=r.get("src") or src_default))
print("rows read:", len(rows))

# Manual decisions after reviewing the flags (see notes in README):
#  - Mont de la Fouly (VS list) and Monte Lema (TI list) carry coordinates copied
#    from a neighbouring row; the true spot is unknown here, so they are left out.
#  - Gurten sits on the Swiss Plateau, not in the Bernese Alps.
for r in rows:
    if (r["name"], r["src"]) in {("Mont de la Fouly", "VS"), ("Monte Lema", "TI")}:
        r["bad"] = "coords copied from neighbour row"
    if r["name"] == "Gurten":
        r["rng"] = "Swiss Plateau"

# 1) bounding box
for r in rows:
    if not (45.80 <= r["lat"] <= 47.85 and 5.90 <= r["lon"] <= 10.55):
        r["bad"] = "outside CH bbox"

# 2) range-bbox outliers: a peak far outside the area its own range covers
by_range = defaultdict(list)
for r in rows:
    if r["rng"]:
        by_range[r["rng"]].append(r)
for rng, lst in by_range.items():
    for r in lst:
        others = [o for o in lst if base(o["name"]) != base(r["name"])]
        if len(others) < 3:
            continue
        la = sorted(o["lat"] for o in others); lo = sorted(o["lon"] for o in others)
        # trimmed box (drop 5% each side) so one bad row doesn't widen it
        t = max(1, len(la) // 20) if len(la) > 20 else 0
        la, lo = la[t:len(la) - t], lo[t:len(lo) - t]
        dlat = max(0, la[0] - r["lat"], r["lat"] - la[-1]) * 111
        dlon = max(0, lo[0] - r["lon"], r["lon"] - lo[-1]) * 76
        if rng in ("Jura Mountains", "Swiss Plateau"):
            continue  # long, sparse chains: box test is meaningless
        if math.hypot(dlat, dlon) > 30:
            r["bad"] = f"{math.hypot(dlat, dlon):.0f} km outside {rng}"

# 3) different names sharing the same spot (copy errors)
for i, a in enumerate(rows):
    for b in rows[i + 1:]:
        if base(a["name"]) != base(b["name"]) and km((a["lat"], a["lon"]), (b["lat"], b["lon"])) < 0.05 \
                and a["h"] != b["h"]:
            if a.get("bad") or b.get("bad"):
                continue  # one of them is already known bad; the other keeps its spot
            for x in (a, b):
                x["bad"] = f"same coords as another peak ({a['name']} / {b['name']})"

for r in rows:
    if r.get("bad"):
        print("FLAG:", r["src"], r["name"], r["lat"], r["lon"], "->", r["bad"])

# 4) merge rows describing the same summit: same base name within 3 km,
#    or any name within 300 m with height within 15 m
peaks = []
for r in rows:
    for p in peaks:
        d = km((r["lat"], r["lon"]), (p["lat"], p["lon"]))
        pn = p["rows"][0]["name"]
        same = (base(r["name"]) == base(pn) and d < 3) or (d < 0.3 and abs(r["h"] - p["rows"][0]["h"]) <= 15)
        if same:
            p["rows"].append(r); break
    else:
        peaks.append(dict(lat=r["lat"], lon=r["lon"], rows=[r]))

def vote(vals):
    """Most common value; ties -> max (OCR-ish typos usually drop digits)."""
    c = defaultdict(int)
    for v in vals: c[v] += 1
    best = max(c.values())
    return max(v for v in c if c[v] == best)

merged, dropped = [], []
for p in peaks:
    good = [r for r in p["rows"] if not r.get("bad")]
    if not good:
        dropped.append(p["rows"][0]); continue
    name = min((r["name"] for r in good), key=lambda n: (len(n), n)) if len({base(r['name']) for r in good}) == 1 else good[0]["name"]
    # prefer the name from the cantonal list (first good row) but strip "/alt" names for the small screen
    name = good[0]["name"].split("/")[0].strip()
    h = vote([r["h"] for r in good])
    prom = vote([r["p"] for r in good])
    lat = sorted(r["lat"] for r in good)[len(good) // 2]
    lon = sorted(r["lon"] for r in good)[len(good) // 2]
    rng = vote([r["rng"] for r in good if r["rng"]] or [""])
    merged.append(dict(name=name, h=h, p=prom, lat=lat, lon=lon, rng=rng,
                       srcs=sorted({r["src"] for r in good}), n=len(good)))

# Rows that were all flagged: report so they can be fixed by hand
for r in dropped:
    print("DROPPED (all sources flagged):", r["name"], r["src"])

# Leftover conflicts: same base name, two merged entries far apart
by_base = defaultdict(list)
for m in merged:
    by_base[base(m["name"])].append(m)
for k, lst in by_base.items():
    if len(lst) > 1:
        for a in lst:
            for b in lst:
                if a is not b and km((a["lat"], a["lon"]), (b["lat"], b["lon"])) < 3:
                    print("NEAR-DUP:", a["name"], b["name"])

merged.sort(key=lambda m: -m["p"])
with open(os.path.join(out, "peaks_merged.json"), "w", encoding="utf-8") as f:
    json.dump(merged, f, ensure_ascii=False, indent=0)
print("merged peaks:", len(merged))
cnt = defaultdict(int)
for m in merged: cnt[m["rng"]] += 1
for k, v in sorted(cnt.items(), key=lambda kv: -kv[1]): print(f"  {v:4d}  {k}")
