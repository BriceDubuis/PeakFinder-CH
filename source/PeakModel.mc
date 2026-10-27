import Toybox.Application;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

class Peak {
    var name as String;
    var lat as Float;
    var lon as Float;
    var elev as Number;
    var prom as Number;
    var massif as Number;
    var dist as Float = 0.0f;   // km from the watch
    var brg as Float = 0.0f;    // degrees from true north

    function initialize(n as String, la as Float, lo as Float, e as Number, p as Number, m as Number) {
        name = n;
        lat = la;
        lon = lo;
        elev = e;
        prom = p;
        massif = m;
    }
}

// Holds the watch position and the short list of summits around it.
// Only one data tile is in memory at a time; the result list is capped.
class PeakModel {
    const MAX_PEAKS = 30;
    const RELOAD_KM = 1.0f;

    var lat as Float? = null;
    var lon as Float? = null;
    var alt as Float? = null;
    var quality as Number = 0;
    var peaks as Array<Peak> = [] as Array<Peak>;
    var radiusIdx as Number = 1;
    var promIdx as Number = 0;

    private var _loadLat as Float? = null;
    private var _loadLon as Float? = null;
    private var _massifs as Array<String>? = null;

    function initialize() {
        radiusIdx = storedIndex("radiusIdx", 1);
        promIdx = storedIndex("promIdx", 0);
    }

    private function storedIndex(key as String, fallback as Number) as Number {
        var v = Application.Storage.getValue(key);
        if (v instanceof Number) {
            var n = v as Number;
            if (n >= 0 && n < 4) {
                return n;
            }
        }
        return fallback;
    }

    function radiusKm() as Number {
        return [10, 20, 40, 80][radiusIdx];
    }

    function minProm() as Number {
        return [150, 300, 500, 1000][promIdx];
    }

    function cycleRadius() as Void {
        radiusIdx = (radiusIdx + 1) % 4;
        Application.Storage.setValue("radiusIdx", radiusIdx);
        reload();
    }

    function cycleProm() as Void {
        promIdx = (promIdx + 1) % 4;
        Application.Storage.setValue("promIdx", promIdx);
        reload();
    }

    function massifName(i as Number) as String {
        if (_massifs == null) {
            _massifs = WatchUi.loadResource(Rez.JsonData.massifs) as Array<String>;
        }
        var m = _massifs;
        if (m != null && i >= 0 && i < m.size()) {
            return m[i];
        }
        return "";
    }

    function setPosition(la as Float, lo as Float, al as Float?, q as Number) as Void {
        lat = la;
        lon = lo;
        alt = al;
        quality = q;
        var ll = _loadLat;
        var lo0 = _loadLon;
        if (ll == null || lo0 == null || Geo.distanceKm(la, lo, ll, lo0) > RELOAD_KM) {
            reload();
        } else {
            updateGeometry();
        }
    }

    // Rebuild the list from the tiles that overlap the search circle.
    function reload() as Void {
        var la = lat;
        var lo = lon;
        if (la == null || lo == null) {
            return;
        }
        _loadLat = la;
        _loadLon = lo;
        peaks = [] as Array<Peak>;   // free the old list before loading tiles

        var radius = radiusKm().toFloat();
        var cosLat = Math.cos(Math.toRadians(la)).toFloat();
        var dLat = radius / Geo.KM_PER_DEG;
        var dLon = radius / (Geo.KM_PER_DEG * cosLat);
        var r0 = Math.floor((la - dLat - TileIndex.LAT0) / TileIndex.DEG).toNumber();
        var r1 = Math.floor((la + dLat - TileIndex.LAT0) / TileIndex.DEG).toNumber();
        var c0 = Math.floor((lo - dLon - TileIndex.LON0) / TileIndex.DEG).toNumber();
        var c1 = Math.floor((lo + dLon - TileIndex.LON0) / TileIndex.DEG).toNumber();

        var keep = [] as Array<Peak>;
        for (var r = r0; r <= r1; r++) {
            for (var c = c0; c <= c1; c++) {
                var rid = TileIndex.resourceFor(r, c);
                if (rid != null) {
                    // one cosine per tile, taken half-way to the tile centre:
                    // within 0.05 % of an exact distance, and cheap on the watch
                    var midLat = (la + TileIndex.LAT0 + (r + 0.5f) * TileIndex.DEG) / 2.0f;
                    var cosMid = Math.cos(Math.toRadians(midLat)).toFloat();
                    scanTile(rid, la, lo, cosMid, radius, keep);
                }
            }
        }
        peaks = keep;
        updateGeometry();
    }

    // Tile layout: [ [names...], [latE4, lonE4, elev, prom, massif, ...] ],
    // sorted by prominence, most prominent first.
    private function scanTile(rid as ResourceId, la as Float, lo as Float, cosLat as Float,
                              radius as Float, keep as Array<Peak>) as Void {
        var tile = WatchUi.loadResource(rid) as Array;
        var names = tile[0] as Array<String>;
        var data = tile[1] as Array<Number>;
        var minP = minProm();
        for (var i = 0; i < names.size(); i++) {
            var o = i * 5;
            var prom = data[o + 3];
            if (prom < minP) {
                break;   // the rest of this tile is less prominent
            }
            var n = keep.size();
            if (n >= MAX_PEAKS && prom <= keep[n - 1].prom) {
                break;   // list is full of more important summits
            }
            var pla = data[o].toFloat() / 10000.0f;
            var plo = data[o + 1].toFloat() / 10000.0f;
            if (Geo.fastKm(la, lo, pla, plo, cosLat) > radius) {
                continue;
            }
            var p = new Peak(names[i], pla, plo, data[o + 2], prom, data[o + 4]);
            if (n < MAX_PEAKS) {
                keep.add(p);
            } else {
                keep[n - 1] = p;   // replace the least prominent
            }
            // keep the list ordered by prominence
            var j = keep.size() - 1;
            while (j > 0 && keep[j - 1].prom < keep[j].prom) {
                var t = keep[j - 1];
                keep[j - 1] = keep[j];
                keep[j] = t;
                j--;
            }
        }
    }

    function updateGeometry() as Void {
        var la = lat;
        var lo = lon;
        if (la == null || lo == null) {
            return;
        }
        for (var i = 0; i < peaks.size(); i++) {
            var p = peaks[i];
            p.dist = Geo.distanceKm(la, lo, p.lat, p.lon);
            p.brg = Geo.bearingDeg(la, lo, p.lat, p.lon);
        }
    }

    // Summit whose bearing is closest to the direction the watch points.
    function closestToBearing(heading as Float) as Peak? {
        var best = null;
        var bestD = 999.0f;
        for (var i = 0; i < peaks.size(); i++) {
            var d = Geo.relDeg(peaks[i].brg, heading).abs();
            if (d < bestD) {
                bestD = d;
                best = peaks[i];
            }
        }
        return best;
    }

    // Copy of the list sorted by distance (insertion sort, n <= 30).
    function byDistance() as Array<Peak> {
        var out = [] as Array<Peak>;
        for (var i = 0; i < peaks.size(); i++) {
            var p = peaks[i];
            out.add(p);
            var j = out.size() - 1;
            while (j > 0 && out[j - 1].dist > p.dist) {
                out[j] = out[j - 1];
                j--;
            }
            out[j] = p;
        }
        return out;
    }
}
