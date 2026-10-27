import Toybox.Lang;
import Toybox.Math;
import Toybox.Sensor;

// Small-distance geometry. Inside a 100 km radius the flat-earth
// (equirectangular) approximation is off by far less than the data's own
// precision, and it is much cheaper than haversine on the watch.
module Geo {
    const KM_PER_DEG = 111.195f;
    const EARTH_M = 6371000.0f;
    const REFRACTION = 0.13f;

    function fastKm(la1 as Float, lo1 as Float, la2 as Float, lo2 as Float, cosLat as Float) as Float {
        var x = (lo2 - lo1) * cosLat;
        var y = la2 - la1;
        return (Math.sqrt(x * x + y * y) * KM_PER_DEG).toFloat();
    }

    function distanceKm(la1 as Float, lo1 as Float, la2 as Float, lo2 as Float) as Float {
        var cosLat = Math.cos(Math.toRadians((la1 + la2) / 2.0f)).toFloat();
        return fastKm(la1, lo1, la2, lo2, cosLat);
    }

    // Bearing from point 1 to point 2, degrees clockwise from true north.
    function bearingDeg(la1 as Float, lo1 as Float, la2 as Float, lo2 as Float) as Float {
        var cosLat = Math.cos(Math.toRadians((la1 + la2) / 2.0f));
        var x = (lo2 - lo1) * cosLat;
        var y = la2 - la1;
        return norm360(Math.toDegrees(Math.atan2(x, y)).toFloat());
    }

    function norm360(a as Float) as Float {
        while (a < 0.0f) { a += 360.0f; }
        while (a >= 360.0f) { a -= 360.0f; }
        return a;
    }

    // Signed difference a - b folded into -180..180.
    function relDeg(a as Float, b as Float) as Float {
        var d = norm360(a - b);
        return d > 180.0f ? d - 360.0f : d;
    }

    function cardinal(b as Float) as String {
        var names = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"];
        return names[((b + 22.5f) / 45.0f).toNumber() % 8];
    }

    // Angle above (+) or below (-) the horizon at which the summit appears,
    // with earth curvature and standard refraction. Null if altitude unknown.
    function elevationAngleDeg(peakM as Number, userM as Float?, distKm as Float) as Float? {
        if (userM == null || distKm < 0.05f) {
            return null;
        }
        var d = distKm * 1000.0f;
        var drop = d * d / (2.0f * EARTH_M) * (1.0f - REFRACTION);
        return Math.toDegrees(Math.atan((peakM - userM - drop) / d)).toFloat();
    }

    // Compass heading in degrees, or null when the watch has no compass reading.
    function headingDeg() as Float? {
        if (Toybox has :Sensor) {
            var info = Sensor.getInfo();
            if (info has :heading && info.heading != null) {
                return norm360(Math.toDegrees(info.heading as Float).toFloat());
            }
        }
        return null;
    }

    function formatKm(d as Float) as String {
        return d < 10.0f ? d.format("%.1f") + " km" : d.format("%.0f") + " km";
    }
}
