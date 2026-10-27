import Toybox.Application;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.WatchUi;

class PeakFinderApp extends Application.AppBase {
    var model as PeakModel;

    function initialize() {
        AppBase.initialize();
        model = new PeakModel();
    }

    function onStart(state as Dictionary?) as Void {
        onPosition(Position.getInfo());   // last known fix, so summits show at once
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        if (Toybox has :Sensor) {
            Sensor.enableSensorEvents(method(:onSensor));   // keeps the compass running
        }
    }

    function onStop(state as Dictionary?) as Void {
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        if (Toybox has :Sensor) {
            Sensor.enableSensorEvents(null);
        }
    }

    function onPosition(info as Position.Info) as Void {
        var pos = info.position;
        if (pos == null || info.accuracy == Position.QUALITY_NOT_AVAILABLE) {
            return;
        }
        var deg = pos.toDegrees();
        model.setPosition(deg[0].toFloat(), deg[1].toFloat(), info.altitude, info.accuracy as Number);
        WatchUi.requestUpdate();
    }

    function onSensor(info as Sensor.Info) as Void {
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new RadarView();
        return [view, new RadarDelegate(view)];
    }
}

function getApp() as PeakFinderApp {
    return Application.getApp() as PeakFinderApp;
}

function getModel() as PeakModel {
    return $.getApp().model;
}
