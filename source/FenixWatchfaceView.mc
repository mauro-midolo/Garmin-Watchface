using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.ActivityMonitor;
using Toybox.Activity;
using Toybox.Position;
using Toybox.Application as App;
using Toybox.Weather;

class FenixWatchfaceView extends Ui.WatchFace {

    hidden var lastSunCalcDay = -1;
    hidden var cachedSunrise = null;
    hidden var cachedSunset = null;
    hidden var cachedTomorrowSunrise = null;

    // Raggio del cerchio su cui sono distribuiti i campi dati.
    hidden const FIELD_RADIUS = 88;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {}
    function onShow() {}
    function onHide() {}
    function onExitSleep() {}
    function onEnterSleep() {
        Ui.requestUpdate();
    }

    function onUpdate(dc) {
        var width  = dc.getWidth();
        var height = dc.getHeight();
        var cx = width / 2;
        var cy = height / 2;

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        // Centro: orario grande + data dd/mm/yy
        drawCenterTime(dc, cx, cy);
        drawCenterDate(dc, cx, cy);

        // Cornice circolare sottile per richiamare il profilo dell'orologio
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(cx, cy, FIELD_RADIUS + 18);
        dc.setPenWidth(1);

        // Campi dati radiali alle 8 posizioni (45° tra l'una e l'altra).
        // L'angolo è misurato dal nord, in senso orario.
        drawFieldHR        (dc, polarX(cx,   0), polarY(cy,   0));   // 12
        drawFieldWeather   (dc, polarX(cx,  45), polarY(cy,  45));   // 1:30
        drawFieldFloors    (dc, polarX(cx,  90), polarY(cy,  90));   // 3
        drawFieldSun       (dc, polarX(cx, 135), polarY(cy, 135));   // 4:30
        drawFieldAltitude  (dc, polarX(cx, 180), polarY(cy, 180));   // 6
        drawFieldSteps     (dc, polarX(cx, 225), polarY(cy, 225));   // 7:30
        drawFieldBattery   (dc, polarX(cx, 270), polarY(cy, 270));   // 9
        // 10:30 (315°) lasciato libero per simmetria visiva
    }

    // ----- Geometria radiale -----

    hidden function polarX(cx, deg) {
        return cx + FIELD_RADIUS * Math.sin(deg * Math.PI / 180.0);
    }

    hidden function polarY(cy, deg) {
        return cy - FIELD_RADIUS * Math.cos(deg * Math.PI / 180.0);
    }

    // ----- Centro: orario + data -----

    hidden function drawCenterTime(dc, cx, cy) {
        var clock = Sys.getClockTime();
        var is24 = Sys.getDeviceSettings().is24Hour;
        var hour = clock.hour;
        if (!is24) {
            hour = hour % 12;
            if (hour == 0) { hour = 12; }
        }
        var timeStr = Lang.format("$1$:$2$", [
            hour.format("%02d"),
            clock.min.format("%02d")
        ]);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 8, Gfx.FONT_NUMBER_THAI_HOT, timeStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawCenterDate(dc, cx, cy) {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var dateStr = Lang.format("$1$/$2$/$3$", [
            info.day.format("%02d"),
            info.month.format("%02d"),
            (info.year % 100).format("%02d")
        ]);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 32, Gfx.FONT_TINY, dateStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // ----- Campi dati -----

    hidden function drawFieldHR(dc, cx, cy) {
        var hr = readHeartRate();
        var hrStr = (hr != null) ? hr.toString() : "--";

        drawHeartIcon(dc, cx - 16, cy + 1, 10);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx - 4, cy, Gfx.FONT_XTINY, hrStr,
            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawFieldWeather(dc, cx, cy) {
        var cond = null;
        var tempStr = "--";
        if (Toybox has :Weather) {
            var current = Weather.getCurrentConditions();
            if (current != null) {
                cond = current.condition;
                if (current.temperature != null) {
                    var t = current.temperature;
                    if (Sys.getDeviceSettings().temperatureUnits
                            == Sys.UNIT_STATUTE) {
                        t = (t * 9.0 / 5.0) + 32.0;
                    }
                    tempStr = t.toNumber().toString() + "°";
                }
            }
        }
        WeatherIcons.draw(dc, cx, cy - 8, 18, cond);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 12, Gfx.FONT_XTINY, tempStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawFieldFloors(dc, cx, cy) {
        var info = ActivityMonitor.getInfo();
        var floors = 0;
        var floorGoal = 0;
        if (info != null) {
            if (info has :floorsClimbed && info.floorsClimbed != null) {
                floors = info.floorsClimbed;
            }
            if (info has :floorsClimbedGoal && info.floorsClimbedGoal != null) {
                floorGoal = info.floorsClimbedGoal;
            }
        }
        drawStairsIcon(dc, cx, cy - 8, 12);
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        var s = (floorGoal > 0)
            ? Lang.format("$1$/$2$", [floors, floorGoal])
            : floors.toString();
        dc.drawText(cx, cy + 10, Gfx.FONT_XTINY, s,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawFieldSun(dc, cx, cy) {
        var label = "--";
        var timeStr = "--:--";
        var isSunrise = true;

        var loc = getLocation();
        if (loc != null) {
            updateSunCache(loc[0], loc[1]);
            var next = nextSunEvent();
            if (next != null) {
                isSunrise = next[:isSunrise];
                label = isSunrise ? "ALBA" : "TRAM";
                timeStr = formatLocalHM(next[:moment]);
            }
        }

        var color = isSunrise ? Gfx.COLOR_YELLOW : Gfx.COLOR_ORANGE;
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 9, Gfx.FONT_XTINY, label,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 8, Gfx.FONT_XTINY, timeStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawFieldAltitude(dc, cx, cy) {
        var alt = null;
        var info = Activity.getActivityInfo();
        if (info != null && info has :altitude && info.altitude != null) {
            alt = info.altitude;
        }
        var altStr = "--";
        var unit = "m";
        if (alt != null) {
            if (Sys.getDeviceSettings().elevationUnits == Sys.UNIT_STATUTE) {
                alt = alt * 3.28084;
                unit = "ft";
            }
            altStr = alt.toNumber().toString() + unit;
        }
        drawMountainIcon(dc, cx, cy - 8, 12);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 10, Gfx.FONT_XTINY, altStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawFieldSteps(dc, cx, cy) {
        var info = ActivityMonitor.getInfo();
        var steps = (info != null && info.steps != null) ? info.steps : 0;

        drawFootIcon(dc, cx, cy - 8, 12);
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 10, Gfx.FONT_XTINY, steps.toString(),
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawFieldBattery(dc, cx, cy) {
        var stats = Sys.getSystemStats();
        var batt = (stats != null && stats.battery != null) ? stats.battery : 0.0;
        var battInt = batt.toNumber();

        var color = Gfx.COLOR_GREEN;
        if (battInt <= 20) { color = Gfx.COLOR_RED; }
        else if (battInt <= 40) { color = Gfx.COLOR_YELLOW; }

        var bw = 22;
        var bh = 11;
        var tipW = 2;
        var tipH = 5;
        var bx = cx - (bw + tipW) / 2;
        var by = cy - bh - 4;

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(bx, by, bw, bh, 2);
        dc.fillRectangle(bx + bw, by + (bh - tipH) / 2, tipW, tipH);

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        var fillW = (bw - 2) * battInt / 100;
        if (fillW > 0) {
            dc.fillRectangle(bx + 1, by + 1, fillW, bh - 2);
        }

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 8, Gfx.FONT_XTINY,
            battInt.toString() + "%",
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // ----- Icone vettoriali -----

    hidden function drawHeartIcon(dc, cx, cy, size) {
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        var r = size / 2;
        dc.fillCircle(cx - r / 2, cy - r / 3, r);
        dc.fillCircle(cx + r / 2, cy - r / 3, r);
        var pts = [
            [cx - r - 1, cy - 1],
            [cx + r + 1, cy - 1],
            [cx,         cy + r + 2]
        ];
        dc.fillPolygon(pts);
    }

    hidden function drawMountainIcon(dc, cx, cy, size) {
        dc.setColor(Gfx.COLOR_DK_GREEN, Gfx.COLOR_TRANSPARENT);
        var h = size;
        var w = size + 4;
        var baseY = cy + h / 2;
        var pts = [
            [cx - w / 2, baseY],
            [cx,         cy - h / 2],
            [cx + w / 2, baseY]
        ];
        dc.fillPolygon(pts);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var tipPts = [
            [cx - 2, cy - h / 2 + 4],
            [cx,     cy - h / 2],
            [cx + 2, cy - h / 2 + 4]
        ];
        dc.fillPolygon(tipPts);
    }

    hidden function drawStairsIcon(dc, cx, cy, size) {
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        var step = size / 3;
        var w = size;
        // 3 gradini ascendenti
        dc.fillRectangle(cx - w / 2,         cy + step,       w,         step - 1);
        dc.fillRectangle(cx - w / 2 + step,  cy,              w - step,  step - 1);
        dc.fillRectangle(cx - w / 2 + 2*step,cy - step,       w - 2*step,step - 1);
    }

    hidden function drawFootIcon(dc, cx, cy, size) {
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        // pianta del piede ovale + 4 dita
        var w = size / 2;
        var h = size * 3 / 4;
        dc.fillCircle(cx, cy + 2, w);
        // dita: 4 cerchietti sopra
        for (var i = -1; i <= 2; i++) {
            var dx = (i - 0.5) * 3;
            dc.fillCircle(cx + dx, cy - h / 2 + 1, 1);
        }
    }

    // ----- Helpers HR / Posizione / Sole -----

    hidden function readHeartRate() {
        var actInfo = Activity.getActivityInfo();
        if (actInfo != null && actInfo.currentHeartRate != null) {
            return actInfo.currentHeartRate;
        }
        var iter = ActivityMonitor.getHeartRateHistory(1, true);
        if (iter != null) {
            var sample = iter.next();
            if (sample != null
                    && sample.heartRate != null
                    && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                return sample.heartRate;
            }
        }
        return null;
    }

    hidden function getLocation() {
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            var deg = info.position.toDegrees();
            if (deg != null && deg.size() >= 2) {
                var lat = deg[0];
                var lon = deg[1];
                if (lat != 0.0 || lon != 0.0) {
                    saveLocation(lat, lon);
                    return [lat, lon];
                }
            }
        }
        var app = App.getApp();
        var sLat = app.getProperty("lastLat");
        var sLon = app.getProperty("lastLon");
        if (sLat != null && sLon != null) {
            return [sLat, sLon];
        }
        return null;
    }

    hidden function saveLocation(lat, lon) {
        var app = App.getApp();
        app.setProperty("lastLat", lat);
        app.setProperty("lastLon", lon);
    }

    hidden function updateSunCache(lat, lon) {
        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var dayKey = info.year * 10000 + info.month * 100 + info.day;
        if (dayKey != lastSunCalcDay) {
            var res = SunCalc.compute(lat, lon, now);
            cachedSunrise = res.get("sunrise");
            cachedSunset  = res.get("sunset");

            var tomorrow = now.add(new Time.Duration(86400));
            var resT = SunCalc.compute(lat, lon, tomorrow);
            cachedTomorrowSunrise = resT.get("sunrise");

            lastSunCalcDay = dayKey;
        }
    }

    hidden function nextSunEvent() {
        var nowVal = Time.now().value();
        if (cachedSunrise != null && nowVal < cachedSunrise.value()) {
            return { :isSunrise => true, :moment => cachedSunrise };
        }
        if (cachedSunset != null && nowVal < cachedSunset.value()) {
            return { :isSunrise => false, :moment => cachedSunset };
        }
        if (cachedTomorrowSunrise != null) {
            return { :isSunrise => true, :moment => cachedTomorrowSunrise };
        }
        return null;
    }

    hidden function formatLocalHM(moment) {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        var is24 = Sys.getDeviceSettings().is24Hour;
        var h = info.hour;
        if (!is24) {
            h = h % 12;
            if (h == 0) { h = 12; }
        }
        return Lang.format("$1$:$2$", [h.format("%02d"), info.min.format("%02d")]);
    }
}
