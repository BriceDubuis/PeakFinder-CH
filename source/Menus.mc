import Toybox.Lang;
import Toybox.WatchUi;

function radiusLabel() as String {
    return $.getModel().radiusKm().toString() + " km";
}

function promLabel() as String {
    return "at least " + $.getModel().minProm().toString() + " m";
}

// Hold UP on the main screen
function pushMainMenu() as Void {
    var menu = new WatchUi.Menu2({:title => "PeakFinder"});
    menu.addItem(new WatchUi.MenuItem("Nearby list", "sorted by distance", :list, null));
    menu.addItem(new WatchUi.MenuItem("Radius", $.radiusLabel(), :radius, null));
    menu.addItem(new WatchUi.MenuItem("Prominence", $.promLabel(), :prom, null));
    WatchUi.pushView(menu, new MainMenuDelegate(), WatchUi.SLIDE_UP);
}

class MainMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        var m = $.getModel();
        if (id == :list) {
            pushNearbyList();
        } else if (id == :radius) {
            m.cycleRadius();
            item.setSubLabel($.radiusLabel());
            WatchUi.requestUpdate();
        } else if (id == :prom) {
            m.cycleProm();
            item.setSubLabel($.promLabel());
            WatchUi.requestUpdate();
        }
    }

    private function pushNearbyList() as Void {
        var list = $.getModel().byDistance();
        var menu = new WatchUi.Menu2({:title => "Nearby (" + list.size().toString() + ")"});
        if (list.size() == 0) {
            menu.addItem(new WatchUi.MenuItem("No summit", "in range", -1, null));
        }
        for (var i = 0; i < list.size(); i++) {
            var p = list[i];
            menu.addItem(new WatchUi.MenuItem(p.name,
                Geo.formatKm(p.dist) + " " + Geo.cardinal(p.brg) + "  " + p.elev.toString() + " m",
                i, null));
        }
        WatchUi.pushView(menu, new NearbyListDelegate(list), WatchUi.SLIDE_LEFT);
    }
}

class NearbyListDelegate extends WatchUi.Menu2InputDelegate {
    private var _list as Array<Peak>;

    function initialize(list as Array<Peak>) {
        Menu2InputDelegate.initialize();
        _list = list;
    }

    function onSelect(item as MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Number) {
            var idx = id as Number;
            if (idx >= 0 && idx < _list.size()) {
                var v = new DetailView(_list, idx);
                WatchUi.pushView(v, new DetailDelegate(v), WatchUi.SLIDE_LEFT);
            }
        }
    }
}
