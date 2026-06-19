using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.ActivityMonitor;
using Toybox.Activity;
using Toybox.Application as App;
using Toybox.Weather;

class FenixWatchfaceView extends Ui.WatchFace {

    // Stato di alimentazione: true quando l'orologio è "sveglio" e onUpdate
    // viene chiamato ogni secondo (high-power mode); false in low-power mode,
    // quando onUpdate è chiamato al più una volta al minuto. I secondi vengono
    // mostrati solo quando isAwake è true, cioè quando sono effettivamente
    // aggiornati in tempo reale.
    hidden var isAwake = true;

    hidden var lastSunCalcDay = -1;
    hidden var cachedSunrise = null;
    hidden var cachedSunset = null;
    hidden var cachedTomorrowSunrise = null;
    hidden var cachedCivilDawn = null;
    hidden var cachedCivilDusk = null;

    // Cache della fase lunare: ricalcolata una sola volta al giorno (vedi
    // ensureMoonData). cachedMoonFraction = frazione illuminata del disco
    // (0 = novilunio, 1 = plenilunio); cachedMoonWaxing = true se la luna è
    // crescente (limbo illuminato a destra, convenzione emisfero nord);
    // cachedMoonPhaseIndex = indice 0..7 della fase canonica.
    hidden var lastMoonCalcDay = -1;
    hidden var cachedMoonFraction = 0.0;
    hidden var cachedMoonWaxing = true;
    hidden var cachedMoonPhaseIndex = 0;

    // Mese sinodico medio (giorni tra due noviluni consecutivi): periodo del
    // ciclo delle fasi lunari usato per il calcolo astronomico.
    const SYNODIC_MONTH = 29.530588853;

    // Raggio dei campi: calcolato una sola volta in onLayout in base alle
    // dimensioni reali dello schermo. Tenuto leggermente dentro le tacche orarie.
    hidden var FIELD_RADIUS = 88;

    // Geometria dello schermo, calcolata una sola volta in onLayout
    hidden var screenW = 0;
    hidden var screenH = 0;
    hidden var centerX = 0;
    hidden var centerY = 0;

    function initialize() {
        WatchFace.initialize();
    }

    // onLayout: inizializzazione del layout. Eseguito una sola volta: calcola
    // la geometria dello schermo.
    function onLayout(dc) {
        screenW = dc.getWidth();
        screenH = dc.getHeight();
        centerX = screenW / 2;
        centerY = screenH / 2;
        FIELD_RADIUS = (centerX * 0.75).toNumber();
    }

    // onShow: la watchface torna visibile → aggiorniamo la cache del sole
    // (i dati di alba/tramonto potrebbero essere cambiati).
    function onShow() {
        ensureSunData();
    }

    function onHide() {}

    // onExitSleep: l'orologio torna in high-power mode → onUpdate sarà chiamato
    // ogni secondo. Riattiviamo la visualizzazione dei secondi.
    function onExitSleep() {
        isAwake = true;
        Ui.requestUpdate();
    }

    // onEnterSleep: l'orologio passa in low-power mode → onUpdate non sarà più
    // chiamato ogni secondo. Nascondiamo i secondi (non sarebbero aggiornati in
    // tempo reale) e forziamo un ultimo redraw per rimuoverli dallo schermo.
    function onEnterSleep() {
        isAwake = false;
        Ui.requestUpdate();
    }


    function onUpdate(dc) {
        var cx = centerX;
        var cy = centerY;

        // Dati semi-statici: alba/tramonto, ricalcolati solo al cambio giorno.
        ensureSunData();

        // Fase lunare: puro calcolo astronomico, ricalcolato solo al cambio
        // giorno (mai in onPartialUpdate, per rispettare il power budget).
        ensureMoonData();

        // Layer 0: sfondo (anello fasi del giorno + tacche orarie)
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        drawPhaseRing(dc, cx, cy);

        // Layer 1: indicatore dell'ora corrente (dinamico, cambia ogni minuto)
        drawNowIndicator(dc, cx, cy, cx - 3);

        // Layer 2: orario, separatore blu, data
        drawCenterTime(dc, cx, cy);
        dc.setColor(0x0066CC, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cx - 38, cy + 19, cx + 38, cy + 19);
        drawCenterDate(dc, cx, cy);

        // Secondi correnti (0–59): mostrati come testo SOPRA l'orario, con font
        // più piccolo (FONT_XTINY) rispetto al FONT_NUMBER_MEDIUM dell'orario.
        // Aggiornati solo qui, in onUpdate; volutamente NON ridisegnati in
        // onPartialUpdate.
        drawCenterSeconds(dc, cx, cy);

        // Icona telefono connesso (sopra l'orario); nessun indicatore se non connesso
        drawPhoneIcon(dc, cx, cy);

        // Fase lunare (glifo vettoriale sotto la data)
        drawMoonPhase(dc, cx, cy);

        // Layer 3: campi dati radiali (slot da 30°, posizionati tra le tacche)
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
            return;
        }

        var sr   = momentToLocalMin(cachedSunrise);
        var ss   = momentToLocalMin(cachedSunset);
        var dawn = (cachedCivilDawn != null) ? momentToLocalMin(cachedCivilDawn) : sr;
        var dusk = (cachedCivilDusk != null) ? momentToLocalMin(cachedCivilDusk) : ss;

        drawPhaseArc(dc, cx, cy, r, 0,    dawn, Gfx.COLOR_BLUE);
        drawPhaseArc(dc, cx, cy, r, dawn, sr,   Gfx.COLOR_RED);
        drawPhaseArc(dc, cx, cy, r, sr,   ss,   Gfx.COLOR_YELLOW);
        drawPhaseArc(dc, cx, cy, r, ss,   dusk, Gfx.COLOR_RED);
        drawPhaseArc(dc, cx, cy, r, dusk, 1440, Gfx.COLOR_BLUE);

        // Tacche orarie bianche sopra i colori (l'indicatore dell'ora corrente
        // è dinamico e viene disegnato in onUpdate, non nel buffer statico)
        drawHourTicks(dc, cx, cy);
    }

    hidden function drawHourTicks(dc, cx, cy) {
        for (var i = 0; i < 24; i++) {
            var rad = i * 15.0 * Math.PI / 180.0;
            var sinA = Math.sin(rad);
            var cosA = Math.cos(rad);
            var isCardinal = (i % 6 == 0);
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

    // Secondi sopra l'orario, font più piccolo dell'orario. Disegnati solo in
    // onUpdate: NON vengono ridisegnati in onPartialUpdate.
    // Mostrati esclusivamente quando l'orologio è sveglio (isAwake): in
    // low-power mode onUpdate viene chiamato al più una volta al minuto, quindi
    // i secondi sarebbero un valore fermo e fuorviante → li nascondiamo.
    hidden function drawCenterSeconds(dc, cx, cy) {
        if (!isAwake) { return; }
        var seconds = Sys.getClockTime().sec;
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 50, Gfx.FONT_MEDIUM, seconds.format("%02d"),
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
        drawValue(dc, x, y + 9, s, Gfx.COLOR_WHITE);
    }

    hidden function drawFieldSun(dc, x, y) {
        // La cache di alba/tramonto è aggiornata in onUpdate via ensureSunData()
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
        // La cache di alba/tramonto è aggiornata in onUpdate via ensureSunData()
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
        drawValue(dc, x, y + 9, steps.toString(), Gfx.COLOR_WHITE);
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

    // Posizione usata solo per il calcolo astronomico di alba/tramonto.
    // Ricavata dalla località di osservazione del meteo (Toybox.Weather), che
    // segue la posizione del telefono/orologio senza richiedere il GPS. Il
    // valore viene messo in cache in Storage e riutilizzato quando il meteo non
    // è ancora disponibile.
    hidden function getLocation() {
        if (Toybox has :Weather) {
            var current = Weather.getCurrentConditions();
            if (current != null
                    && (current has :observationLocationPosition)
                    && current.observationLocationPosition != null) {
                var deg = current.observationLocationPosition.toDegrees();
                if (deg != null && deg.size() >= 2) {
                    var lat = deg[0];
                    var lon = deg[1];
                    if (lat != 0.0 || lon != 0.0) {
                        saveLocation(lat, lon);
                        return [lat, lon];
                    }
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
                lat, lon, now, SunCalc.ZENITH_CIVIL);
            cachedCivilDawn = resTw.get("sunrise");
            cachedCivilDusk = resTw.get("sunset");

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

    // ----- Fase lunare -----

    // Calcola la fase lunare a partire dalla sola data corrente: puro calcolo
    // astronomico, NESSUN sensore, GPS o chiamata di rete. Eseguito UNA SOLA
    // VOLTA AL GIORNO (guardia sul day-key, come ensureSunData): il risultato
    // resta in cache e viene riusato a ogni onUpdate senza ricalcolare.
    //
    // FORMULA: si misura l'"età" della luna come tempo trascorso da un
    // novilunio di riferimento noto, riportato nel mese sinodico medio
    // (~29.53 giorni). La frazione del ciclo (0..1) dà fase e illuminazione.
    hidden function ensureMoonData() {
        var now = Time.now();
        var info = Gregorian.info(now, Time.FORMAT_SHORT);
        var dayKey = info.year * 10000 + info.month * 100 + info.day;
        if (dayKey == lastMoonCalcDay) { return; }

        // Novilunio di riferimento: 6 gennaio 2000, 18:14 UTC (JD ~2451550.1),
        // istante di novilunio comunemente usato come epoca nei calcoli lunari.
        var refNewMoon = Gregorian.moment({
            :year => 2000, :month => 1, :day => 6,
            :hour => 18, :minute => 14, :second => 0
        });

        // Giorni trascorsi dal novilunio di riferimento.
        var elapsedDays = now.subtract(refNewMoon).value() / 86400.0;

        // Frazione del ciclo sinodico corrente: phase in [0, 1).
        //   0   = novilunio, 0.5 = plenilunio.
        var phase = elapsedDays / SYNODIC_MONTH;
        phase = phase - Math.floor(phase);
        if (phase < 0.0) { phase += 1.0; }

        // Frazione illuminata del disco: 0 (novilunio) → 1 (plenilunio) → 0.
        cachedMoonFraction = (1.0 - Math.cos(2.0 * Math.PI * phase)) / 2.0;
        // Crescente nella prima metà del ciclo (limbo illuminato a destra),
        // calante nella seconda metà (limbo a sinistra).
        cachedMoonWaxing = (phase < 0.5);
        // Indice 0..7 delle 8 fasi canoniche (0 = novilunio, 1 = crescente,
        // 2 = primo quarto, 3 = gibbosa crescente, 4 = plenilunio,
        // 5 = gibbosa calante, 6 = ultimo quarto, 7 = calante).
        cachedMoonPhaseIndex = (Math.floor(phase * 8.0 + 0.5)).toNumber() % 8;

        lastMoonCalcDay = dayKey;
    }

    // Disegna il glifo della luna nella fase corrente, vettorialmente con dc:
    // disco in ombra + regione illuminata costruita come un unico poligono
    // delimitato dal limbo circolare e dal terminatore (semi-ellisse). In low
    // power mode resta leggero (nessun calcolo: legge solo la cache).
    //
    // POSIZIONE E DIMENSIONE: per spostare/ridimensionare l'icona modifica
    // "mx"/"my" (centro) e "R" (raggio) qui sotto.
    hidden function drawMoonPhase(dc, cx, cy) {
        var mx = cx;          // centro X: colonna centrale
        var my = cy + 62;     // centro Y: spazio libero sotto la data
        var R  = 13;          // raggio del disco lunare

        // Disco in ombra + contorno (sempre visibile, anche al novilunio).
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_BLACK);
        dc.fillCircle(mx, my, R);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(mx, my, R);

        var f = cachedMoonFraction;
        // k: posizione orizzontale del terminatore relativa al limbo (-1..1).
        //   f=0  → k=1  (terminatore sul limbo: nessuna porzione illuminata)
        //   f=.5 → k=0  (terminatore verticale: mezzo disco illuminato)
        //   f=1  → k=-1 (terminatore sul limbo opposto: disco pieno)
        var k = 1.0 - 2.0 * f;
        var sign = cachedMoonWaxing ? 1.0 : -1.0;   // crescente → lato destro

        // Regione illuminata come poligono unico: si scende lungo il limbo
        // circolare e si risale lungo il terminatore (semi-ellisse di
        // semilarghezza k volte quella del limbo a ciascuna quota).
        var N = 16;
        var pts = new [2 * (N + 1)];
        for (var i = 0; i <= N; i++) {
            // limbo: dall'alto (y=-R) verso il basso (y=+R)
            var y = -R + (2.0 * R) * i / N;
            var d = (R * R) - (y * y);
            if (d < 0.0) { d = 0.0; }
            var xl = Math.sqrt(d);
            pts[i] = [ (mx + sign * xl).toNumber(), (my + y).toNumber() ];
            // terminatore: dal basso (y=+R) verso l'alto (y=-R)
            var yt = R - (2.0 * R) * i / N;
            var dt = (R * R) - (yt * yt);
            if (dt < 0.0) { dt = 0.0; }
            var xlt = Math.sqrt(dt);
            pts[N + 1 + i] = [ (mx + sign * k * xlt).toNumber(),
                               (my + yt).toNumber() ];
        }

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
        dc.setPenWidth(1);
    }

    // ----- Icona telefono connesso -----

    // Disegna un'icona "smartphone" vettoriale (nessuna PNG) sopra l'orario,
    // SOLO quando il telefono è connesso. Quando non è connesso non viene
    // mostrato alcun indicatore.
    hidden function drawPhoneIcon(dc, cx, cy) {
        var ds = Sys.getDeviceSettings();
        var connected = (ds has :phoneConnected) ? (ds.phoneConnected == true) : false;
        if (!connected) { return; }

        var w = 14;              // larghezza del corpo del telefono
        var h = 24;              // altezza del corpo del telefono
        var x = cx - w / 2;
        var y = (cy - 90) - h / 2;

        // Corpo del telefono (rettangolo arrotondato bianco)
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, w, h, 3);

        // Schermo (interno nero)
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x + 2, y + 4, w - 4, h - 8, 1);

        // Altoparlante (linea in alto) e tasto home (punto in basso)
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillRectangle(cx - 2, y + 2, 4, 1);
        dc.fillCircle(cx, y + h - 2, 1);
    }

}
