using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang;
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
    hidden var cachedLat = null;
    hidden var cachedLon = null;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {
    }

    function onShow() {
    }

    function onHide() {
    }

    function onExitSleep() {
    }

    function onEnterSleep() {
        Ui.requestUpdate();
    }

    function onUpdate(dc) {
        var width  = dc.getWidth();
        var height = dc.getHeight();
        var cx = width / 2;
        var cy = height / 2;

        // Clear screen
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        drawTime(dc, cx, cy);
        drawDate(dc, cx, cy);
        drawHeartRate(dc, cx, cy);
        drawWeather(dc, cx, cy);
        drawSun(dc, cx, cy);
        drawSteps(dc, cx, cy, width, height);
        drawBattery(dc, cx, cy, width, height);
        drawFloors(dc, cx, cy, width, height);
    }

    hidden function drawTime(dc, cx, cy) {
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
        dc.drawText(cx, cy - 60, Gfx.FONT_NUMBER_THAI_HOT, timeStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawDate(dc, cx, cy) {
        var info = Gregorian.info(Time.now(), Time.FORMAT_MEDIUM);
        var dateStr = Lang.format("$1$ $2$ $3$", [
            info.day_of_week,
            info.day,
            info.month
        ]);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 5, Gfx.FONT_XTINY, dateStr.toUpper(),
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawSun(dc, cx, cy) {
        var label = "ALBA";
        var timeStr = "--:--";
        var isSunrise = true;

        var loc = getLocation();
        if (loc != null) {
            updateSunCache(loc[0], loc[1]);
            var next = nextSunEvent();
            if (next != null) {
                isSunrise = next[:isSunrise];
                label = isSunrise ? "ALBA" : "TRAMONTO";
                timeStr = formatLocalHM(next[:moment]);
            }
        }

        var y = cy + 45;
        var color = isSunrise ? Gfx.COLOR_YELLOW : Gfx.COLOR_ORANGE;

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, y, Gfx.FONT_XTINY, label,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, y + 16, Gfx.FONT_TINY, timeStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // Restituisce il prossimo evento solare (alba/tramonto) rispetto ad ora.
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

    hidden function drawHeartRate(dc, cx, cy) {
        var hr = null;

        var actInfo = Activity.getActivityInfo();
        if (actInfo != null && actInfo.currentHeartRate != null) {
            hr = actInfo.currentHeartRate;
        }

        if (hr == null) {
            var iter = ActivityMonitor.getHeartRateHistory(1, true);
            if (iter != null) {
                var sample = iter.next();
                if (sample != null
                        && sample.heartRate != null
                        && sample.heartRate != ActivityMonitor.INVALID_HR_SAMPLE) {
                    hr = sample.heartRate;
                }
            }
        }

        var x = cx - 55;
        var y = cy + 18;

        drawHeartIcon(dc, x - 14, y, 10);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var hrStr = (hr != null) ? hr.toString() : "--";
        dc.drawText(x + 4, y, Gfx.FONT_TINY, hrStr,
            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

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

    hidden function drawWeather(dc, cx, cy) {
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

        var x = cx + 38;
        var y = cy + 18;

        WeatherIcons.draw(dc, x, y, 22, cond);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x + 16, y, Gfx.FONT_TINY, tempStr,
            Gfx.TEXT_JUSTIFY_LEFT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawSteps(dc, cx, cy, width, height) {
        var info = ActivityMonitor.getInfo();
        var steps = (info != null && info.steps != null) ? info.steps : 0;
        var goal  = (info != null && info.stepGoal != null) ? info.stepGoal : 0;

        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        var stepStr = (goal > 0)
            ? Lang.format("$1$ / $2$", [steps, goal])
            : steps.toString();
        dc.drawText(cx, height - 48, Gfx.FONT_TINY, stepStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawBattery(dc, cx, cy, width, height) {
        var stats = Sys.getSystemStats();
        var batt = (stats != null && stats.battery != null) ? stats.battery : 0.0;
        var battInt = batt.toNumber();

        var color = Gfx.COLOR_GREEN;
        if (battInt <= 20) {
            color = Gfx.COLOR_RED;
        } else if (battInt <= 40) {
            color = Gfx.COLOR_YELLOW;
        }

        // Bottom-left: battery icon + percent
        var bx = 20;
        var by = height - 22;
        var bw = 26;
        var bh = 12;

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawRectangle(bx, by, bw, bh);
        dc.fillRectangle(bx + bw, by + 3, 3, bh - 6);

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        var fillW = (bw - 2) * battInt / 100;
        if (fillW > 0) {
            dc.fillRectangle(bx + 1, by + 1, fillW, bh - 2);
        }

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(bx + bw / 2 + 5, by - 14, Gfx.FONT_XTINY,
            battInt.toString() + "%",
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawFloors(dc, cx, cy, width, height) {
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

        // Bottom-right
        var rightX = width - 20;
        var valueY = height - 22;

        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        var floorStr = (floorGoal > 0)
            ? Lang.format("$1$/$2$", [floors, floorGoal])
            : floors.toString();
        dc.drawText(rightX, valueY, Gfx.FONT_TINY, floorStr,
            Gfx.TEXT_JUSTIFY_RIGHT | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // ----- Helpers -----

    hidden function getLocation() {
        var info = Position.getInfo();
        if (info != null && info.position != null) {
            var deg = info.position.toDegrees();
            if (deg != null && deg.size() >= 2) {
                var lat = deg[0];
                var lon = deg[1];
                if (lat != 0.0 || lon != 0.0) {
                    cachedLat = lat;
                    cachedLon = lon;
                    saveLocation(lat, lon);
                    return [lat, lon];
                }
            }
        }
        // Fallback alla posizione salvata
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
