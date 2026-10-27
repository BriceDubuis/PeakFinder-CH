import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.Timer;
import Toybox.WatchUi;

// Main screen: a compass ring with the summits around you. The ring turns
// with the watch, so the summit at the top marker is the one you face.
// Its name, height, distance and the angle to look up are shown inside.
class RadarView extends WatchUi.View {
    var selected as Peak? = null;
    var manual as Boolean = false;   // true after UP/DOWN until BACK
    private var _timer as Timer.Timer?;

    function initialize() {
        View.initialize();
    }

    function onShow() as Void {
        var t = new Timer.Timer();
        t.start(method(:onTick), 400, true);
        _timer = t;
    }

    function onHide() as Void {
        var t = _timer;
        if (t != null) {
            t.stop();
        }
        _timer = null;
    }

    function onTick() as Void {
        WatchUi.requestUpdate();
    }

    // Move the selection to the next summit clockwise (dir = 1) or anticlockwise (-1).
    function step(dir as Number) as Void {
        var peaks = $.getModel().peaks;
        if (peaks.size() == 0) {
            return;
        }
        var cur = selected;
        if (cur == null || peaks.indexOf(cur) < 0) {
            selected = peaks[0];
        } else {
            var best = null;
            var bestD = 999.0f;
            for (var i = 0; i < peaks.size(); i++) {
                var p = peaks[i];
                if (p != cur) {
                    var d = Geo.norm360((p.brg - cur.brg) * dir);
                    if (d == 0.0f) {
                        d = 360.0f;
                    }
                    if (d < bestD) {
                        bestD = d;
                        best = p;
                    }
                }
            }
            if (best != null) {
                selected = best;
            }
        }
        manual = true;
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        var m = $.getModel();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var cy = h / 2;
        var rOut = (w < h ? w : h) / 2 - 4;
        var rIn = rOut * 58 / 100;

        if (m.lat == null) {
            dc.drawText(cx, cy - 20, Graphics.FONT_SMALL, "PeakFinder", Ui.CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 15, Graphics.FONT_TINY, "Searching GPS...", Ui.CENTER);
            dc.drawText(cx, cy + 45, Graphics.FONT_XTINY, "Go outside, sky in view", Ui.CENTER);
            return;
        }

        var heading = Geo.headingDeg();
        var rot = 0.0f;
        if (heading != null) {
            rot = heading;
        }
        var peaks = m.peaks;

        // keep a manual choice while it is still in the list, else follow the compass
        var sel = selected;
        if (sel != null && peaks.indexOf(sel) < 0) {
            sel = null;
            manual = false;
        }
        if (!manual || sel == null) {
            if (peaks.size() == 0) {
                sel = null;
            } else if (heading != null) {
                sel = m.closestToBearing(heading);
            } else if (sel == null) {
                sel = peaks[0];
            }
        }
        selected = sel;

        drawRing(dc, cx, cy, rOut, rIn, rot, heading != null);

        if (peaks.size() == 0) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 12, Graphics.FONT_TINY, "No summit within", Ui.CENTER);
            dc.drawText(cx, cy + 12, Graphics.FONT_TINY, m.radiusKm().toString() + " km", Ui.CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 38, Graphics.FONT_XTINY, "Hold UP: settings", Ui.CENTER);
            drawGps(dc, cx, cy - rIn + 12, m.quality);
            return;
        }

        // summit dots: angle = bearing relative to heading, radius = distance
        var radius = m.radiusKm().toFloat();
        var span = rOut - rIn - 26;
        for (var i = peaks.size() - 1; i >= 0; i--) {   // least prominent first, so big ones stay on top
            var p = peaks[i];
            var a = Math.toRadians(p.brg - rot);
            var f = p.dist / radius;
            if (f > 1.0f) {
                f = 1.0f;
            }
            var rr = rIn + 8 + span * f;
            var x = (cx + rr * Math.sin(a)).toNumber();
            var y = (cy - rr * Math.cos(a)).toNumber();
            var size = p.prom >= 1000 ? 5 : (p.prom >= 500 ? 4 : (p.prom >= 300 ? 3 : 2));
            if (p == sel) {
                dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
                dc.setPenWidth(2);
                dc.drawLine((cx + rIn * Math.sin(a)).toNumber(), (cy - rIn * Math.cos(a)).toNumber(), x, y);
                dc.fillCircle(x, y, size + 2);
                dc.setPenWidth(1);
            } else {
                dc.setColor(p.prom >= 500 ? Graphics.COLOR_WHITE : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
                dc.fillCircle(x, y, size);
            }
        }

        // centre panel
        drawGps(dc, cx, cy - rIn + 12, m.quality);
        if (sel != null) {
            var ang = Geo.elevationAngleDeg(sel.elev, m.alt, sel.dist);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy - 36, Graphics.FONT_XTINY, Ui.angleText(ang), Ui.CENTER);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            var maxW = (2 * Math.sqrt(rIn * rIn - 13 * 13)).toNumber() - 8;
            Ui.drawFitted(dc, cx, cy - 12, sel.name, maxW);
            dc.drawText(cx, cy + 14, Graphics.FONT_TINY, sel.elev.toString() + " m", Ui.CENTER);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, cy + 38, Graphics.FONT_XTINY,
                Geo.formatKm(sel.dist) + " " + Geo.cardinal(sel.brg), Ui.CENTER);
        }
    }

    private function drawRing(dc as Dc, cx as Number, cy as Number, rOut as Number, rIn as Number,
                              rot as Float, hasCompass as Boolean) as Void {
        dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(cx, cy, rIn);
        dc.drawCircle(cx, cy, (rIn + rOut - 10) / 2);   // half-radius distance ring

        // cardinal letters, turning with the watch
        var labels = ["N", "E", "S", "W"];
        var rl = rOut - 10;
        for (var i = 0; i < 4; i++) {
            var a = Math.toRadians(i * 90 - rot);
            dc.setColor(i == 0 ? Graphics.COLOR_RED : Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText((cx + rl * Math.sin(a)).toNumber(), (cy - rl * Math.cos(a)).toNumber(),
                Graphics.FONT_XTINY, labels[i], Ui.CENTER);
        }

        // facing marker at 12 o'clock (only meaningful with a compass)
        if (hasCompass) {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            var top = cy - rOut + 20;
            dc.fillPolygon([[cx, top + 10], [cx - 7, top], [cx + 7, top]]);
        }
    }

    private function drawGps(dc as Dc, x as Number, y as Number, quality as Number) as Void {
        dc.setColor(Ui.gpsColor(quality), Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x, y, 4);
    }
}

class RadarDelegate extends WatchUi.BehaviorDelegate {
    private var _view as RadarView;

    function initialize(view as RadarView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // START: details of the highlighted summit
    function onSelect() as Boolean {
        var p = _view.selected;
        if (p != null) {
            var list = $.getModel().byDistance();
            var idx = list.indexOf(p);
            var v = new DetailView(list, idx < 0 ? 0 : idx);
            WatchUi.pushView(v, new DetailDelegate(v), WatchUi.SLIDE_LEFT);
        }
        return true;
    }

    // DOWN / UP: browse summits around the ring
    function onNextPage() as Boolean {
        _view.step(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.step(-1);
        return true;
    }

    // Hold UP: menu
    function onMenu() as Boolean {
        $.pushMainMenu();
        return true;
    }

    // BACK leaves manual browsing first, then exits
    function onBack() as Boolean {
        if (_view.manual) {
            _view.manual = false;
            WatchUi.requestUpdate();
            return true;
        }
        return false;
    }
}
