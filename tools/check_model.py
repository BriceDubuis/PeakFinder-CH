"""Re-run the watch's tile search in Python and compare with a brute-force
search over all selected peaks (exact haversine), for several spots.

Usage: python3 -I check_model.py <project_dir>
"""
import json, math, os, sys

proj = sys.argv[1]
tiles_dir = os.path.join(proj, "resources", "tiles")
LAT0, LON0, DEG, ROWS, COLS, MAX = 45.75, 5.75, 0.5, 5, 10, 30
KM = 111.195

def load(r, c):
    fn = os.path.join(tiles_dir, f"t_{r}_{c}.json")
    return json.load(open(fn, encoding="utf-8")) if os.path.exists(fn) else None

def fast_km(la, lo, pla, plo, cosl):
    return math.hypot((plo - lo) * cosl, pla - la) * KM

def haversine(la1, lo1, la2, lo2):
    p1, p2 = math.radians(la1), math.radians(la2)
    dp, dl = p2 - p1, math.radians(lo2 - lo1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 6371.0 * 2 * math.asin(math.sqrt(a))

def true_bearing(la1, lo1, la2, lo2):
    p1, p2, dl = math.radians(la1), math.radians(la2), math.radians(lo2 - lo1)
    y = math.sin(dl) * math.cos(p2)
    x = math.cos(p1) * math.sin(p2) - math.sin(p1) * math.cos(p2) * math.cos(dl)
    return (math.degrees(math.atan2(y, x)) + 360) % 360

def watch_search(la, lo, radius, minp):
    """Mirror of PeakModel.reload/scanTile, including the early breaks."""
    cosl = math.cos(math.radians(la))
    dlat, dlon = radius / KM, radius / (KM * cosl)
    r0, r1 = math.floor((la - dlat - LAT0) / DEG), math.floor((la + dlat - LAT0) / DEG)
    c0, c1 = math.floor((lo - dlon - LON0) / DEG), math.floor((lo + dlon - LON0) / DEG)
    keep = []
    for r in range(r0, r1 + 1):
        for c in range(c0, c1 + 1):
            if not (0 <= r < ROWS and 0 <= c < COLS):
                continue
            t = load(r, c)
            if not t:
                continue
            names, data = t
            cosmid = math.cos(math.radians((la + LAT0 + (r + 0.5) * DEG) / 2))
            for i, nm in enumerate(names):
                o = i * 5
                prom = data[o + 3]
                if prom < minp:
                    break
                if len(keep) >= MAX and prom <= keep[-1][1]:
                    break
                pla, plo = data[o] / 1e4, data[o + 1] / 1e4
                if fast_km(la, lo, pla, plo, cosmid) > radius:
                    continue
                item = (nm, prom, pla, plo, data[o + 2])
                if len(keep) < MAX:
                    keep.append(item)
                else:
                    keep[-1] = item
                j = len(keep) - 1
                while j > 0 and keep[j - 1][1] < keep[j][1]:
                    keep[j - 1], keep[j] = keep[j], keep[j - 1]
                    j -= 1
    return keep

def brute(la, lo, radius, minp):
    allp = []
    for fn in os.listdir(tiles_dir):
        if not fn.startswith("t_"):
            continue
        names, data = json.load(open(os.path.join(tiles_dir, fn), encoding="utf-8"))
        for i, nm in enumerate(names):
            o = i * 5
            pla, plo = data[o] / 1e4, data[o + 1] / 1e4
            if data[o + 3] >= minp and haversine(la, lo, pla, plo) <= radius:
                allp.append((nm, data[o + 3]))
    allp.sort(key=lambda x: -x[1])
    return allp

spots = {
    "Zermatt": (46.0207, 7.7491), "Grindelwald": (46.6244, 8.0414),
    "Pontresina": (46.4959, 9.9013), "Lugano": (46.0037, 8.9511),
    "Chasseral hotel": (47.1330, 7.0590), "Zurich HB": (47.3779, 8.5403),
    "Geneva": (46.2044, 6.1432), "Paris (outside)": (48.8566, 2.3522),
}
ok = True
for name, (la, lo) in spots.items():
    for radius in (10, 20, 40, 80):
        for minp in (150, 300, 500, 1000):
            w = watch_search(la, lo, radius, minp)
            b = brute(la, lo, radius, minp)
            # The watch's result must equal the exact top-MAX for some radius
            # within +-0.5 % (flat-earth vs haversine at the very edge),
            # allowing ties in prominence at the cut-off.
            wset = {x[0] for x in w}
            matched = False
            for k in range(-10, 11):
                b = brute(la, lo, radius * (1 + k * 0.0005), minp)
                if len(b) <= MAX:
                    if {n for n, _ in b} == wset:
                        matched = True; break
                    continue
                cutoff = b[MAX - 1][1]
                must = {n for n, p in b if p > cutoff}
                may = {n for n, p in b if p == cutoff}
                if must <= wset <= must | may and len(wset) == MAX:
                    matched = True; break
            if not matched:
                ok = False
                print("MISMATCH", name, radius, minp)
    w = watch_search(la, lo, 20, 150)
    top = ", ".join(f"{n} {haversine(la, lo, pla, plo):.1f}km {true_bearing(la, lo, pla, plo):.0f}°"
                    for n, p, pla, plo, e in w[:4])
    print(f"{name:16s} 20km/150m: {len(w):2d} peaks  {top}")

# bearing / distance accuracy of the watch's flat-earth formulas, worst case at 80 km
worst_d = worst_b = 0.0
for la, lo in spots.values():
    if la > 48: continue
    for ang in range(0, 360, 15):
        la2 = la + 80 / KM * math.cos(math.radians(ang))
        lo2 = lo + 80 / (KM * math.cos(math.radians(la))) * math.sin(math.radians(ang))
        cosm = math.cos(math.radians((la + la2) / 2))
        fd = math.hypot((lo2 - lo) * cosm, la2 - la) * KM
        fb = (math.degrees(math.atan2((lo2 - lo) * cosm, la2 - la)) + 360) % 360
        hd = haversine(la, lo, la2, lo2); hb = true_bearing(la, lo, la2, lo2)
        worst_d = max(worst_d, abs(fd - hd) / hd)
        worst_b = max(worst_b, abs((fb - hb + 180) % 360 - 180))
print(f"flat-earth error at 80 km: distance {worst_d*100:.2f} %, bearing {worst_b:.2f}°")
print("ALL OK" if ok else "PROBLEMS FOUND")
