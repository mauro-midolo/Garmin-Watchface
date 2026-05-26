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
    hidden var cachedAstroDawn = null;
    hidden var cachedAstroDusk = null;

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

        // Aggiorna alba/tramonto/crepuscolo per la posizione corrente.
        ensureSunData();

        // Centro: orario grande + data dd/mm/yy
        drawCenterTime(dc, cx, cy);
        drawCenterDate(dc, cx, cy);

        // Anello 24h: archi colorati per fase del giorno + indicatore ora.
        drawPhaseRing(dc, cx, cy);

        // Campi dati radiali alle 8 posizioni (45° tra l'una e l'altra).
        // L'angolo è misurato dal nord, in senso orario.
        drawFieldHR        (dc, polarX(cx,   0), polarY(cy,   0));   // 12
        drawFieldWeather   (dc, polarX(cx,  45), polarY(cy,  45));   // 1:30
        drawFieldFloors    (dc, polarX(cx,  90), polarY(cy,  90));   // 3
        drawFieldSun       (dc, polarX(cx, 135), polarY(cy, 135));   // 4:30
        drawFieldAltitude  (dc, polarX(cx, 180), polarY(cy, 180));   // 6
        drawFieldSteps     (dc, polarX(cx, 225), polarY(cy, 225));   // 7:30
        drawFieldBattery   (dc, polarX(cx, 270), polarY(cy, 270));   // 9
        drawFieldTempRange (dc, polarX(cx, 315), polarY(cy, 315));   // 10:30
    }

    // ----- Geometria radiale -----

    hidden function polarX(cx, deg) {
        return cx + FIELD_RADIUS * Math.sin(deg * Math.PI / 180.0);
    }

    hidden function polarY(cy, deg) {
        return cy - FIELD_RADIUS * Math.cos(deg * Math.PI / 180.0);
    }

    // ----- Anello 24h delle fasi del giorno -----

    // Disegna l'anello con archi colorati proporzionali a ciascuna fase:
    //   blu   = notte (buio)
    //   rosso = crepuscolo (mattutino e serale)
    //   giallo= luce piena (alba -> tramonto)
    // Mezzanotte in alto, il tempo scorre in senso orario. Sopra, l'indicatore
    // dell'ora corrente (barretta bianca con bordo nero).
    hidden function drawPhaseRing(dc, cx, cy) {
        var r = FIELD_RADIUS + 18;
        dc.setPenWidth(3);

        if (cachedSunrise == null || cachedSunset == null) {
            // Nessun dato solare: anello interamente blu.
            dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r);
            drawNowIndicator(dc, cx, cy, r);
            return;
        }

        var sr = momentToLocalMin(cachedSunrise);
        var ss = momentToLocalMin(cachedSunset);
        // Bordi del crepuscolo astronomico; se assenti (es. estate alle alte
        // latitudini) coincidono con alba/tramonto -> nessuna fascia rossa.
        var dawn = (cachedAstroDawn != null) ? momentToLocalMin(cachedAstroDawn) : sr;
        var dusk = (cachedAstroDusk != null) ? momentToLocalMin(cachedAstroDusk) : ss;

        // notte | crepuscolo mattutino | luce piena | crepuscolo serale | notte
        drawPhaseArc(dc, cx, cy, r, 0,    dawn, Gfx.COLOR_BLUE);
        drawPhaseArc(dc, cx, cy, r, dawn, sr,   Gfx.COLOR_RED);
        drawPhaseArc(dc, cx, cy, r, sr,   ss,   Gfx.COLOR_YELLOW);
        drawPhaseArc(dc, cx, cy, r, ss,   dusk, Gfx.COLOR_RED);
        drawPhaseArc(dc, cx, cy, r, dusk, 1440, Gfx.COLOR_BLUE);

        drawNowIndicator(dc, cx, cy, r);
    }

    // Arco fra due minuti del giorno [0..1440]. Con mezzanotte in alto e tempo
    // orario l'angolo bussola (da nord, orario) vale min/4; drawArc usa invece
    // 0°=ore 3, crescente in senso antiorario, da cui la conversione 90 - C.
    hidden function drawPhaseArc(dc, cx, cy, radius, startMin, endMin, color) {
        if (endMin - startMin < 1) { return; }
        var ga = normDeg(90.0 - (startMin / 4.0));
        var gb = normDeg(90.0 - (endMin   / 4.0));
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Gfx.ARC_CLOCKWISE, ga, gb);
    }

    // Barretta bianca con bordo nero, radiale, posizionata sull'ora corrente.
    hidden function drawNowIndicator(dc, cx, cy, radius) {
        var clock = Sys.getClockTime();
        var nowMin = clock.hour * 60 + clock.min;
        var rad = (nowMin / 4.0) * Math.PI / 180.0;
        var sinA = Math.sin(rad);
        var cosA = Math.cos(rad);

        // Bordo nero (penna più larga).
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(7);
        dc.drawLine(cx + (radius - 8) * sinA, cy - (radius - 8) * cosA,
                    cx + (radius + 8) * sinA, cy - (radius + 8) * cosA);

        // Barretta bianca al centro.
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(3);
        dc.drawLine(cx + (radius - 6) * sinA, cy - (radius - 6) * cosA,
                    cx + (radius + 6) * sinA, cy - (radius + 6) * cosA);

        dc.setPenWidth(1);
    }

    hidden function momentToLocalMin(moment) {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return info.hour * 60 + info.min;
    }

    hidden function normDeg(d) {
        while (d < 0.0)    { d += 360.0; }
        while (d >= 360.0) { d -= 360.0; }
        return d;
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

    // Massima e minima previste per la giornata corrente (Toybox.Weather),
    // su un'unica riga "max°/min°". Stesso stile icona+valore degli altri campi.
    hidden function drawFieldTempRange(dc, cx, cy) {
        var hiStr = "--";
        var loStr = "--";
        if (Toybox has :Weather) {
            var current = Weather.getCurrentConditions();
            if (current != null) {
                var statute = (Sys.getDeviceSettings().temperatureUnits
                        == Sys.UNIT_STATUTE);
                if (current.highTemperature != null) {
                    var hi = current.highTemperature;
                    if (statute) { hi = (hi * 9.0 / 5.0) + 32.0; }
                    hiStr = hi.toNumber().toString();
                }
                if (current.lowTemperature != null) {
                    var lo = current.lowTemperature;
                    if (statute) { lo = (lo * 9.0 / 5.0) + 32.0; }
                    loStr = lo.toNumber().toString();
                }
            }
        }
        drawThermometerIcon(dc, cx, cy - 8, 12);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 10, Gfx.FONT_XTINY,
            hiStr + "°/" + loStr + "°",
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

        var next = nextSunEvent();
        if (next != null) {
            isSunrise = next[:isSunrise];
            label = isSunrise ? "ALBA" : "TRAM";
            timeStr = formatLocalHM(next[:moment]);
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

    hidden function drawThermometerIcon(dc, cx, cy, size) {
        var stemW  = size / 4;
        var bulbR  = size / 4 + 1;
        var topY   = cy - size / 2;
        var bulbCy = cy + size / 2 - bulbR;

        // Involucro bianco: stelo + bulbo
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(cx - stemW / 2, topY, stemW, bulbCy - topY,
            stemW / 2);
        dc.fillCircle(cx, bulbCy, bulbR);

        // Mercurio rosso: bulbo pieno + colonnina
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(cx, bulbCy, bulbR - 1);
        dc.fillRectangle(cx - 1, cy - size / 4, 2, bulbCy - (cy - size / 4));
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

    hidden function ensureSunData() {
        var loc = getLocation();
        if (loc != null) {
            updateSunCache(loc[0], loc[1]);
        }
    }

    hidden function updateSunCache(lat, lon) {
        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var dayKey = info.year * 10000 + info.month * 100 + info.day;
        if (dayKey != lastSunCalcDay) {
            var res = SunCalc.compute(lat, lon, now);
            cachedSunrise = res.get("sunrise");
            cachedSunset  = res.get("sunset");

            var resTw = SunCalc.computeWithZenith(
                lat, lon, now, SunCalc.ZENITH_ASTRONOMICAL);
            cachedAstroDawn = resTw.get("sunrise");
            cachedAstroDusk = resTw.get("sunset");

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
