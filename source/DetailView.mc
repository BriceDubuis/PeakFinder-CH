import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

// One summit: arrow toward it, height, prominence, distance, bearing,
// how far above the horizon to look, and its massif.
class DetailView extends WatchUi.View {
    var list as Array<Peak>;
    var index as Number;
    private var _timer as Timer.Timer?;

    function initialize(peaks as Array<Peak>, idx as Number) {
        View.initialize();
        list = peaks;
        index = idx;
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

    function step(dir as Number) as Void {
        var n = list.size();
        if (n > 0) {
            index = (index + dir + n) % n;
            WatchUi.requestUpdate();
        }
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        if (list.size() == 0) {
            dc.drawText(cx, h / 2, Graphics.FONT_SMALL, "No summit", Ui.CENTER);
            return;
        }
        var p = list[index];
        var m = $.getModel();

        // distance and bearing from the current position (the list may be older)
        var dist = p.dist;
        var brg = p.brg;
        var la = m.lat;
        var lo = m.lon;
        if (la != null && lo != null) {
            dist = Geo.distanceKm(la, lo, p.lat, p.lon);
            brg = Geo.bearingDeg(la, lo, p.lat, p.lon);
        }

        // name
        Ui.drawFitted(dc, cx, h * 17 / 100, p.name, w * 70 / 100);

        // arrow: relative to the compass, or north-up without one
        var heading = Geo.headingDeg();
        var ay = h * 40 / 100;
        if (heading != null) {
            var rel = Geo.relDeg(brg, heading);
            dc.setColor(rel.abs() <= 5.0f ? Graphics.COLOR_GREEN : Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            Ui.drawArrow(dc, cx, ay, h * 12 / 100, rel);
        } else {
            dc.setColor(Graphics.COLOR_ORANGE, Graphics.COLOR_TRANSPARENT);
            Ui.drawArrow(dc, cx, ay, h * 12 / 100, brg);
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx + h * 20 / 100, ay, Graphics.FONT_XTINY, "N-up", Ui.CENTER);
        }

        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h * 60 / 100, Graphics.FONT_TINY,
            p.elev.toString() + " m   P " + p.prom.toString() + " m", Ui.CENTER);
        dc.drawText(cx, h * 70 / 100, Graphics.FONT_TINY,
            Geo.formatKm(dist) + "  " + brg.format("%.0f") + "° " + Geo.cardinal(brg), Ui.CENTER);

        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        var ang = Geo.elevationAngleDeg(p.elev, m.alt, dist);
        dc.drawText(cx, h * 79 / 100, Graphics.FONT_XTINY,
            ang == null ? "altitude unknown" : "look " + Ui.angleText(ang), Ui.CENTER);
        dc.drawText(cx, h * 87 / 100, Graphics.FONT_XTINY, m.massifName(p.massif), Ui.CENTER);
        dc.drawText(cx, h * 94 / 100, Graphics.FONT_XTINY,
            (index + 1).toString() + "/" + list.size().toString(), Ui.CENTER);
    }
}

class DetailDelegate extends WatchUi.BehaviorDelegate {
    private var _view as DetailView;

    function initialize(view as DetailView) {
        BehaviorDelegate.initialize();
        _view = view;
    }

    // DOWN / UP: next / previous summit by distance
    function onNextPage() as Boolean {
        _view.step(1);
        return true;
    }

    function onPreviousPage() as Boolean {
        _view.step(-1);
        return true;
    }

    function onBack() as Boolean {
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        return true;
    }
}
