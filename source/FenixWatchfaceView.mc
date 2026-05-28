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

    // Raggio dinamico dei campi: calcolato in onUpdate in base alle dimensioni
    // reali dello schermo. Tenuto leggermente dentro le tacche orarie.
    hidden var FIELD_RADIUS = 88;

    // Bitmap icone connettività, caricati una sola volta in onLayout
    hidden var btOnBmp = null;
    hidden var btOffBmp = null;
    hidden var gpsOnBmp = null;
    hidden var gpsOffBmp = null;
    hidden var wifiOnBmp = null;
    hidden var wifiOffBmp = null;

    function initialize() {
        WatchFace.initialize();
    }

    function onLayout(dc) {
        btOnBmp    = Ui.loadResource(Rez.Drawables.BluetoothOn);
        btOffBmp   = Ui.loadResource(Rez.Drawables.BluetoothOff);
        gpsOnBmp   = Ui.loadResource(Rez.Drawables.GpsOn);
        gpsOffBmp  = Ui.loadResource(Rez.Drawables.GpsOff);
        wifiOnBmp  = Ui.loadResource(Rez.Drawables.WifiOn);
        wifiOffBmp = Ui.loadResource(Rez.Drawables.WifiOff);
    }
    function onShow() {}
    function onHide() {}
    function onExitSleep() {}
    function onEnterSleep() {
        Ui.requestUpdate();
    }

    function onPartialUpdate(dc) {
        var cx = dc.getWidth() / 2;
        var cy = dc.getHeight() / 2;

        // Cancella solo l'area centrale (orario + separatore + data)
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.fillRectangle(cx - 55, cy - 35, 110, 80);

        drawCenterTime(dc, cx, cy);
        dc.setColor(0x0066CC, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cx - 38, cy + 19, cx + 38, cy + 19);
        drawCenterDate(dc, cx, cy);
    }

    function onUpdate(dc) {
        var width  = dc.getWidth();
        var height = dc.getHeight();
        var cx = width / 2;
        var cy = height / 2;

        FIELD_RADIUS = (cx * 0.75).toNumber();

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();

        ensureSunData();

        // Layer 1: anello fasi del giorno (esterno) + tacche orarie + indicatore ora
        drawPhaseRing(dc, cx, cy);

        // Layer 3: orario, separatore blu, data
        drawCenterTime(dc, cx, cy);
        dc.setColor(0x0066CC, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cx - 38, cy + 19, cx + 38, cy + 19);
        drawCenterDate(dc, cx, cy);

        // Icone di stato connettività (sopra l'orario)
        drawConnectivityIcons(dc, cx, cy);

        // Layer 4: campi dati radiali (slot da 30°, posizionati tra le tacche)
        drawFieldWeather     (dc, polarX(cx,  45), polarY(cy,  45));  // 1-2
        drawFieldTempRange   (dc, polarX(cx,  75), polarY(cy,  75));  // 2-3
        drawFieldAltitude    (dc, polarX(cx, 105), polarY(cy, 105));  // 3-4
        drawFieldSteps       (dc, polarX(cx, 135), polarY(cy, 135));  // 4-5
        drawFieldSunset      (dc, polarX(cx, 165), polarY(cy, 165));  // 5-6
        drawFieldSun         (dc, polarX(cx, 195), polarY(cy, 195));  // 6-7
        drawFieldFloors      (dc, polarX(cx, 225), polarY(cy, 225));  // 7-8
        drawFieldBatteryDays (dc, polarX(cx, 255), polarY(cy, 255));  // 8-9
        drawFieldBattery     (dc, polarX(cx, 285), polarY(cy, 285));  // 9-10
        drawFieldHR          (dc, polarX(cx, 315), polarY(cy, 315));  // 10-11
    }

    // ----- Geometria radiale -----

    hidden function polarX(cx, deg) {
        return cx + FIELD_RADIUS * Math.sin(deg * Math.PI / 180.0);
    }

    hidden function polarY(cy, deg) {
        return cy - FIELD_RADIUS * Math.cos(deg * Math.PI / 180.0);
    }

    // ----- Anello 24h delle fasi del giorno (cerchio esterno unico) -----

    hidden function drawPhaseRing(dc, cx, cy) {
        var r = cx - 3;  // bordo esterno del ring a cx (tocca il bezel)
        dc.setPenWidth(5);

        if (cachedSunrise == null || cachedSunset == null) {
            dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r);
            drawHourTicks(dc, cx, cy);
            drawNowIndicator(dc, cx, cy, r);
            return;
        }

        var sr   = momentToLocalMin(cachedSunrise);
        var ss   = momentToLocalMin(cachedSunset);
        var dawn = (cachedAstroDawn != null) ? momentToLocalMin(cachedAstroDawn) : sr;
        var dusk = (cachedAstroDusk != null) ? momentToLocalMin(cachedAstroDusk) : ss;

        drawPhaseArc(dc, cx, cy, r, 0,    dawn, Gfx.COLOR_BLUE);
        drawPhaseArc(dc, cx, cy, r, dawn, sr,   Gfx.COLOR_RED);
        drawPhaseArc(dc, cx, cy, r, sr,   ss,   Gfx.COLOR_YELLOW);
        drawPhaseArc(dc, cx, cy, r, ss,   dusk, Gfx.COLOR_RED);
        drawPhaseArc(dc, cx, cy, r, dusk, 1440, Gfx.COLOR_BLUE);

        // Tacche orarie bianche sopra i colori + indicatore ora corrente
        drawHourTicks(dc, cx, cy);
        drawNowIndicator(dc, cx, cy, r);
    }

    hidden function drawHourTicks(dc, cx, cy) {
        for (var i = 0; i < 12; i++) {
            var rad = i * 30.0 * Math.PI / 180.0;
            var sinA = Math.sin(rad);
            var cosA = Math.cos(rad);
            var isCardinal = (i % 3 == 0);
            var outerR = cx - 6;
            var innerR = isCardinal ? (cx - 17) : (cx - 11);
            var x1 = (cx + outerR * sinA).toNumber();
            var y1 = (cy - outerR * cosA).toNumber();
            var x2 = (cx + innerR * sinA).toNumber();
            var y2 = (cy - innerR * cosA).toNumber();
            dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
            dc.setPenWidth(isCardinal ? 2 : 1);
            dc.drawLine(x1, y1, x2, y2);
        }
        dc.setPenWidth(1);
    }

    hidden function drawPhaseArc(dc, cx, cy, radius, startMin, endMin, color) {
        if (endMin - startMin < 1) { return; }
        var ga = normDeg(90.0 - (startMin / 4.0));
        var gb = normDeg(90.0 - (endMin   / 4.0));
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawArc(cx, cy, radius, Gfx.ARC_CLOCKWISE, ga, gb);
    }

    hidden function drawNowIndicator(dc, cx, cy, radius) {
        var clock = Sys.getClockTime();
        var nowMin = clock.hour * 60 + clock.min;
        var rad = (nowMin / 4.0) * Math.PI / 180.0;
        var sinA = Math.sin(rad);
        var cosA = Math.cos(rad);

        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(7);
        dc.drawLine(cx + (radius - 8) * sinA, cy - (radius - 8) * cosA,
                    cx + (radius + 8) * sinA, cy - (radius + 8) * cosA);

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

    // ----- Helper valore campo -----

    hidden function drawValue(dc, x, y, text, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, y, Gfx.FONT_XTINY, text,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
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
        dc.drawText(cx, cy - 8, Gfx.FONT_NUMBER_MEDIUM, timeStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawCenterDate(dc, cx, cy) {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var days = ["DOM", "LUN", "MAR", "MER", "GIO", "VEN", "SAB"];
        var dayName = days[info.day_of_week - 1];
        var dateStr = Lang.format("$1$ $2$/$3$/$4$", [
            dayName,
            info.day.format("%02d"),
            info.month.format("%02d"),
            (info.year % 100).format("%02d")
        ]);
        dc.setColor(0x55BBFF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 35, Gfx.FONT_XTINY, dateStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // ----- Campi dati -----

    hidden function drawFieldHR(dc, x, y) {
        var hr = readHeartRate();
        var hrStr = (hr != null) ? hr.toString() : "--";

        drawHeartIcon(dc, x, y - 8, 6);
        drawValue(dc, x, y + 9, hrStr, Gfx.COLOR_WHITE);
    }

    hidden function drawFieldWeather(dc, x, y) {
        if (!(Toybox has :Weather)) { return; }
        var current = Weather.getCurrentConditions();
        if (current == null) { return; }

        var cond = current.condition;
        var tempStr = null;
        if (current.temperature != null) {
            var t = current.temperature;
            if (Sys.getDeviceSettings().temperatureUnits == Sys.UNIT_STATUTE) {
                t = (t * 9.0 / 5.0) + 32.0;
            }
            tempStr = t.toNumber().toString() + "°";
        }

        WeatherIcons.draw(dc, x, y - 8, 16, cond);
        if (tempStr != null) {
            drawValue(dc, x, y + 11, tempStr, Gfx.COLOR_WHITE);
        }
    }

    // Massima e minima previste per la giornata corrente (Toybox.Weather),
    // su un'unica riga "max°/min°". Stesso stile icona+valore degli altri campi.
    hidden function drawFieldTempRange(dc, x, y) {
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
        drawThermometerIcon(dc, x, y - 8, 12);
        drawValue(dc, x, y + 10, loStr + "°/" + hiStr + "°", Gfx.COLOR_WHITE);
    }

    hidden function drawFieldFloors(dc, x, y) {
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
        drawStairsIcon(dc, x, y - 9, 11);
        var s = (floorGoal > 0)
            ? Lang.format("$1$/$2$", [floors, floorGoal])
            : floors.toString();
        drawValue(dc, x, y + 9, s, 0x55BBFF);
    }

    hidden function drawFieldSun(dc, x, y) {
        var loc = getLocation();
        if (loc != null) { updateSunCache(loc[0], loc[1]); }

        var timeStr = "--:--";
        var nowVal = Time.now().value();
        if (cachedSunrise != null && cachedSunrise.value() > nowVal) {
            timeStr = formatLocalHM(cachedSunrise);
        } else if (cachedTomorrowSunrise != null) {
            timeStr = formatLocalHM(cachedTomorrowSunrise);
        } else if (cachedSunrise != null) {
            timeStr = formatLocalHM(cachedSunrise);
        }

        drawSunHorizonIcon(dc, x, y - 9, 15, Gfx.COLOR_YELLOW, true);
        drawValue(dc, x, y + 9, timeStr, Gfx.COLOR_WHITE);
    }

    hidden function drawFieldSunset(dc, x, y) {
        var loc = getLocation();
        if (loc != null) { updateSunCache(loc[0], loc[1]); }

        var timeStr = "--:--";
        if (cachedSunset != null) {
            timeStr = formatLocalHM(cachedSunset);
        }

        drawSunHorizonIcon(dc, x, y - 9, 15, Gfx.COLOR_ORANGE, false);
        drawValue(dc, x, y + 9, timeStr, Gfx.COLOR_WHITE);
    }

    hidden function drawFieldAltitude(dc, x, y) {
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
        drawMountainIcon(dc, x, y - 8, 12);
        drawValue(dc, x, y + 9, altStr, Gfx.COLOR_WHITE);
    }

    hidden function drawFieldSteps(dc, x, y) {
        var info = ActivityMonitor.getInfo();
        var steps = (info != null && info.steps != null) ? info.steps : 0;

        drawShoeIcon(dc, x, y - 7, 5);
        drawValue(dc, x, y + 9, steps.toString(), Gfx.COLOR_GREEN);
    }

    hidden function drawFieldBattery(dc, x, y) {
        var stats = Sys.getSystemStats();
        var batt = (stats != null && stats.battery != null) ? stats.battery : 0.0;
        var battInt = batt.toNumber();

        var color = Gfx.COLOR_GREEN;
        if (battInt <= 20) { color = Gfx.COLOR_RED; }
        else if (battInt <= 40) { color = Gfx.COLOR_YELLOW; }

        var bw = 18;
        var bh = 9;
        var tipW = 2;
        var tipH = 4;
        var bx = x - (bw + tipW) / 2;
        var by = y - 9 - bh / 2;

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(bx, by, bw, bh, 2);
        dc.fillRectangle(bx + bw, by + (bh - tipH) / 2, tipW, tipH);

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        var fillW = (bw - 2) * battInt / 100;
        if (fillW > 0) {
            dc.fillRectangle(bx + 1, by + 1, fillW, bh - 2);
        }

        drawValue(dc, x, y + 9, battInt.toString() + "%", Gfx.COLOR_WHITE);
    }

    hidden function drawFieldBatteryDays(dc, x, y) {
        var stats = Sys.getSystemStats();
        var daysStr = "--";
        if ((stats has :batteryInDays) && stats.batteryInDays != null) {
            var d = stats.batteryInDays;
            daysStr = d.format("%.0f");
        }
        drawValue(dc, x, y - 8, "Giorni", 0x55BBFF);
        drawValue(dc, x, y + 8, daysStr, Gfx.COLOR_WHITE);
    }

    // ----- Icone vettoriali -----

    hidden function drawHeartIcon(dc, cx, cy, size) {
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        // Poligono derivato dal path SVG (viewBox 16x16, centrato in 8,8).
        // s mappa così che la mezza-altezza del cuore = size pixel.
        var s = size.toFloat() / 7.0;
        var cxi = cx.toNumber();
        var cyi = cy.toNumber();
        var pts = [
            [cxi,                         cyi + (7.0 * s).toNumber()],  // punta bassa
            [cxi + (7.0 * s).toNumber(),  cyi + (0.5 * s).toNumber()],  // spalla destra
            [cxi + (8.0 * s).toNumber(),  cyi - (2.8 * s).toNumber()],  // estremo destra
            [cxi + (7.5 * s).toNumber(),  cyi - (5.0 * s).toNumber()],  // lobo dx alto
            [cxi + (4.0 * s).toNumber(),  cyi - (7.0 * s).toNumber()],  // cima lobo dx
            [cxi + (1.5 * s).toNumber(),  cyi - (6.5 * s).toNumber()],  // tacca dx
            [cxi,                         cyi - (4.5 * s).toNumber()],  // centro tacca
            [cxi - (1.5 * s).toNumber(),  cyi - (6.5 * s).toNumber()],  // tacca sx
            [cxi - (4.0 * s).toNumber(),  cyi - (7.0 * s).toNumber()],  // cima lobo sx
            [cxi - (7.5 * s).toNumber(),  cyi - (5.0 * s).toNumber()],  // lobo sx alto
            [cxi - (8.0 * s).toNumber(),  cyi - (2.8 * s).toNumber()],  // estremo sinistra
            [cxi - (7.0 * s).toNumber(),  cyi + (0.5 * s).toNumber()]   // spalla sinistra
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

    // Termometro con sole – fedele alla SVG: stelo+bulbo a sinistra, sole con raggi a destra.
    hidden function drawThermometerIcon(dc, cx, cy, size) {
        var s = size.toFloat();

        // Termometro (lato sinistro)
        var tx    = cx - (s * 0.30).toNumber();
        var topY  = cy - (s * 0.50).toNumber();
        var bulbR = (s * 0.22).toNumber();
        if (bulbR < 2) { bulbR = 2; }
        var bulbY = cy + (s * 0.28).toNumber();

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(tx - 1, topY, 2, bulbY - topY, 1);
        dc.fillCircle(tx, bulbY, bulbR);

        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(tx, bulbY, bulbR - 1);
        var fillTop = cy - (s * 0.08).toNumber();
        dc.fillRectangle(tx, fillTop, 1, bulbY - fillTop);

        // Sole (lato destro) – raggi su / su-dx / dx / giù-dx come nella SVG
        var sx = cx + (s * 0.12).toNumber();
        var sy = cy - (s * 0.15).toNumber();
        var sr = (s * 0.22).toNumber();
        if (sr < 2) { sr = 2; }

        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(sx, sy, sr);

        dc.setPenWidth(1);
        var rIn  = (sr + 1).toFloat();
        var rOut = (sr + 3).toFloat();
        var angles = [ -90, -45, 0, 45 ];
        for (var i = 0; i < angles.size(); i++) {
            var a = angles[i].toFloat() * Math.PI / 180.0;
            dc.drawLine(
                (sx + rIn  * Math.cos(a)).toNumber(),
                (sy + rIn  * Math.sin(a)).toNumber(),
                (sx + rOut * Math.cos(a)).toNumber(),
                (sy + rOut * Math.sin(a)).toNumber()
            );
        }
    }

    hidden function drawStairsIcon(dc, cx, cy, size) {
        dc.setColor(0x0077DD, Gfx.COLOR_TRANSPARENT);
        var step = size / 3;
        var w = size;
        // 3 gradini ascendenti
        dc.fillRectangle(cx - w / 2,         cy + step,       w,         step - 1);
        dc.fillRectangle(cx - w / 2 + step,  cy,              w - step,  step - 1);
        dc.fillRectangle(cx - w / 2 + 2*step,cy - step,       w - 2*step,step - 1);
    }

    hidden function drawShoeIcon(dc, cx, cy, size) {
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        // Poligono derivato dalla SVG (viewBox 512x512).
        // ys = mezza-altezza, xs = mezza-larghezza (rapporto ~2.15:1).
        var ys = size.toFloat();
        var xs = ys * 2.15;
        var cxi = cx.toNumber();
        var cyi = cy.toNumber();
        var pts = [
            [cxi + (xs *  0.96).toNumber(), cyi - (ys * 0.05).toNumber()],  // punta destra
            [cxi + (xs *  0.12).toNumber(), cyi - (ys * 1.00).toNumber()],  // lacci (top)
            [cxi - (xs *  0.13).toNumber(), cyi - (ys * 0.85).toNumber()],  // lingua
            [cxi - (xs *  0.18).toNumber(), cyi - (ys * 0.63).toNumber()],  // sotto lingua
            [cxi - (xs *  0.55).toNumber(), cyi - (ys * 0.40).toNumber()],  // caviglia
            [cxi - (xs *  0.84).toNumber(), cyi - (ys * 0.75).toNumber()],  // tallone alto
            [cxi - (xs *  0.98).toNumber(), cyi - (ys * 0.73).toNumber()],  // tallone sx
            [cxi - (xs *  0.99).toNumber(), cyi + (ys * 1.00).toNumber()],  // suola sx
            [cxi + (xs *  0.97).toNumber(), cyi + (ys * 1.00).toNumber()],  // suola dx
            [cxi + (xs *  0.96).toNumber(), cyi + (ys * 0.54).toNumber()]   // punta dx basso
        ];
        dc.fillPolygon(pts);
    }

    // Icona alba/tramonto: semisole sull'orizzonte con raggi e freccia.
    // up = true → alba (freccia verso l'alto), false → tramonto (freccia in basso).
    hidden function drawSunHorizonIcon(dc, cx, cy, size, color, up) {
        var hw = size / 2;            // mezza larghezza dell'orizzonte
        var hy = cy + 2;              // linea dell'orizzonte
        var r  = (size / 4.0) + 1.0;  // raggio del semisole

        dc.setColor(color, Gfx.COLOR_TRANSPARENT);

        // Cupola del sole: base piatta appoggiata sull'orizzonte
        var degs = [180, 210, 240, 270, 300, 330, 360];
        var dome = new [degs.size()];
        for (var i = 0; i < degs.size(); i++) {
            var a = degs[i] * Math.PI / 180.0;
            dome[i] = [
                (cx + r * Math.cos(a)).toNumber(),
                (hy + r * Math.sin(a)).toNumber()
            ];
        }
        dc.fillPolygon(dome);

        // Raggi rivolti verso l'alto
        dc.setPenWidth(1);
        var rays = [-55, 0, 55];
        for (var i = 0; i < rays.size(); i++) {
            var a = (rays[i] - 90) * Math.PI / 180.0;
            dc.drawLine(
                cx + (r + 1) * Math.cos(a), hy + (r + 1) * Math.sin(a),
                cx + (r + 3) * Math.cos(a), hy + (r + 3) * Math.sin(a));
        }

        // Linea dell'orizzonte
        dc.drawLine(cx - hw, hy, cx + hw, hy);

        // Freccia di direzione sotto l'orizzonte
        var ay = hy + 2;
        if (up) {
            dc.fillPolygon([[cx, ay], [cx - 3, ay + 4], [cx + 3, ay + 4]]);
        } else {
            dc.fillPolygon([[cx, ay + 4], [cx - 3, ay], [cx + 3, ay]]);
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
        var sLat = App.Storage.getValue("lastLat");
        var sLon = App.Storage.getValue("lastLon");
        if (sLat != null && sLon != null) {
            return [sLat, sLon];
        }
        return null;
    }

    hidden function saveLocation(lat, lon) {
        App.Storage.setValue("lastLat", lat);
        App.Storage.setValue("lastLon", lon);
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

    // ----- Icone stato connettività (Bluetooth, WiFi, GPS) -----

    hidden function drawConnectivityIcons(dc, cx, cy) {
        var ds = Sys.getDeviceSettings();

        // Bluetooth: telefono connesso
        var btActive = (ds has :phoneConnected) ? (ds.phoneConnected == true) : false;

        // WiFi via connectionInfo (CIQ 3.1+)
        var wifiActive = false;
        if ((ds has :connectionInfo) && (ds.connectionInfo != null)) {
            var wifiInfo = ds.connectionInfo.get(:wifi);
            if (wifiInfo != null && (wifiInfo has :state)) {
                wifiActive = (wifiInfo.state != 0);
            }
        }

        // GPS: qualità del fix di posizione
        var gpsActive = false;
        var posInfo = Position.getInfo();
        if (posInfo != null && (posInfo has :accuracy)) {
            gpsActive = (posInfo.accuracy >= Position.QUALITY_USABLE);
        }

        var iconY   = cy - 50;
        var spacing = 30;

        var btBmp = btActive ? btOnBmp : btOffBmp;
        if (btBmp != null) {
            dc.drawBitmap(
                cx - spacing - btBmp.getWidth() / 2,
                iconY - btBmp.getHeight() / 2,
                btBmp);
        }
        var wifiBmp = wifiActive ? wifiOnBmp : wifiOffBmp;
        if (wifiBmp != null) {
            dc.drawBitmap(
                cx - wifiBmp.getWidth() / 2,
                iconY - wifiBmp.getHeight() / 2,
                wifiBmp);
        }
        var gpsBmp = gpsActive ? gpsOnBmp : gpsOffBmp;
        if (gpsBmp != null) {
            dc.drawBitmap(
                cx + spacing - gpsBmp.getWidth() / 2,
                iconY - gpsBmp.getHeight() / 2,
                gpsBmp);
        }
    }

}
