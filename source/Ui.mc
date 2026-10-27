import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

module Ui {
    const CENTER = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    // Draw text centred at (x, y) in the largest font that fits maxW,
    // shortening the text as a last resort.
    function drawFitted(dc as Dc, x as Number, y as Number, text as String, maxW as Number) as Void {
        var fonts = [Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getTextWidthInPixels(text, fonts[i]) <= maxW) {
                dc.drawText(x, y, fonts[i], text, CENTER);
                return;
            }
        }
        var font = Graphics.FONT_XTINY;
        var t = text;
        while (t.length() > 2 && dc.getTextWidthInPixels(t + "..", font) > maxW) {
            t = t.substring(0, t.length() - 1) as String;
        }
        dc.drawText(x, y, font, t + "..", CENTER);
    }

    // Arrow centred at (cx, cy) pointing angleDeg clockwise from screen-up.
    function drawArrow(dc as Dc, cx as Number, cy as Number, len as Number, angleDeg as Float) as Void {
        var a = Math.toRadians(angleDeg);
        var s = Math.sin(a);
        var c = Math.cos(a);
        // tip, right wing, notch, left wing (screen coords, y down), then rotated
        var l = len.toFloat();
        var xs = [0.0f, l * 0.5f, 0.0f, -l * 0.5f];
        var ys = [-l, l * 0.6f, l * 0.3f, l * 0.6f];
        var px = new [4];
        var py = new [4];
        for (var i = 0; i < 4; i++) {
            px[i] = (cx + xs[i] * c - ys[i] * s).toNumber();
            py[i] = (cy + xs[i] * s + ys[i] * c).toNumber();
        }
        dc.fillPolygon([[px[0], py[0]], [px[1], py[1]], [px[2], py[2]], [px[3], py[3]]]);
    }

    function gpsColor(quality as Number) as Number {
        if (quality >= 3) {
            return Graphics.COLOR_GREEN;
        } else if (quality == 2) {
            return Graphics.COLOR_YELLOW;
        }
        return Graphics.COLOR_LT_GRAY;   // last known position
    }

    function angleText(a as Float?) as String {
        if (a == null) {
            return "";
        }
        return (a >= 0.0f ? "+" : "") + a.format("%.1f") + "°";
    }
}
