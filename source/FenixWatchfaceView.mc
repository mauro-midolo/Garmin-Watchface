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
using Toybox.Position;

class FenixWatchfaceView extends Ui.WatchFace {

    // Stato di alimentazione: true quando l'orologio è "sveglio" e onUpdate
    // viene chiamato ogni secondo (high-power mode); false in low-power mode,
    // quando onUpdate è chiamato al più una volta al minuto. I secondi vengono
    // mostrati solo quando isAwake è true, cioè quando sono effettivamente
    // aggiornati in tempo reale.
    hidden var isAwake = true;

    // ----- Cache alba/tramonto -----
    // I momenti astronomici cambiano una volta al giorno: si ricalcolano solo
    // al cambio giorno. Vengono messe in cache anche le stringhe già formattate
    // e gli archi dell'anello, per non rifare Gregorian.info/Lang.format e la
    // conversione in gradi a ogni frame.
    hidden var lastSunCalcDay = -1;
    hidden var lastSunAttemptMin = -1;
    hidden var cachedSunrise = null;
    hidden var cachedSunset = null;
    hidden var cachedTomorrowSunrise = null;
    hidden var cachedCivilDawn = null;
    hidden var cachedCivilDusk = null;
    hidden var cachedSunriseStr = null;
    hidden var cachedSunsetStr = null;
    hidden var cachedTomorrowSunriseStr = null;
    // Archi dell'anello 24h già convertiti in gradi: [ [gradiA, gradiB, colore], ... ]
    hidden var cachedPhaseArcs = null;

    // Cache della fase lunare: ricalcolata una sola volta al giorno (vedi
    // ensureMoonData). cachedMoonFraction = frazione illuminata del disco
    // (0 = novilunio, 1 = plenilunio); cachedMoonWaxing = true se la luna è
    // crescente (limbo illuminato a destra, convenzione emisfero nord);
    // cachedMoonPoly = poligono della regione illuminata, precalcolato.
    hidden var lastMoonCalcDay = -1;
    hidden var cachedMoonFraction = 0.0;
    hidden var cachedMoonWaxing = true;
    hidden var cachedMoonPoly = null;

    // Cache della stringa di data: cambia una volta al giorno.
    hidden var lastDateDay = -1;
    hidden var cachedDateStr = "";

    // Formato orario corrente (12/24h): se l'utente lo cambia dalle impostazioni
    // le stringhe già formattate in cache vanno rigenerate.
    hidden var lastIs24 = null;

    // Mese sinodico medio (giorni tra due noviluni consecutivi): periodo del
    // ciclo delle fasi lunari usato per il calcolo astronomico.
    const SYNODIC_MONTH = 29.530588853;

    // Novilunio di riferimento: 6 gennaio 2000, 18:14 UTC, in secondi dall'epoca
    // Unix. Valore costante e già in UTC: Gregorian.moment() NON è utilizzabile
    // perché interpreta i campi come ora locale (errore fino a ±14 ore).
    const REF_NEW_MOON_EPOCH = 947182440;

    // Geometria dello schermo, calcolata una sola volta in onLayout
    hidden var screenW = 0;
    hidden var screenH = 0;
    hidden var centerX = 0;
    hidden var centerY = 0;
    hidden var ringRadius = 0;

    // Geometria precalcolata in onLayout: gli angoli dei campi dati e delle
    // tacche orarie sono costanti, quindi seno/coseno si calcolano una volta
    // sola invece che ~68 volte per frame.
    hidden var fieldX = null;   // ascisse dei 10 slot radiali
    hidden var fieldY = null;   // ordinate dei 10 slot radiali
    hidden var ticksThin = null;      // [x1,y1,x2,y2, ...] tacche normali
    hidden var ticksCardinal = null;  // [x1,y1,x2,y2, ...] tacche cardinali

    // Stringhe localizzate, caricate una volta sola da resources/strings.
    hidden var dayNames = null;
    hidden var strDays = "";
    hidden var strNoTime = "--:--";
    hidden var strNoValue = "--";

    function initialize() {
        WatchFace.initialize();
    }

    // onLayout: inizializzazione del layout. Eseguito una sola volta: calcola
    // la geometria dello schermo, precalcola le coordinate costanti (campi
    // radiali e tacche orarie) e carica le stringhe localizzate.
    function onLayout(dc) {
        screenW = dc.getWidth();
        screenH = dc.getHeight();
        centerX = screenW / 2;
        centerY = screenH / 2;
        ringRadius = centerX - 3;

        var fieldRadius = centerX * 0.75;
        buildFieldPositions(fieldRadius);
        buildHourTicks();
        loadStrings();
    }

    // Posizioni dei 10 campi dati: slot da 30° a partire da 45°, cioè i settori
    // compresi tra le tacche orarie (1-2, 2-3, ... 10-11).
    hidden function buildFieldPositions(radius) {
        fieldX = new [10];
        fieldY = new [10];
        for (var i = 0; i < 10; i++) {
            var deg = 45.0 + 30.0 * i;
            var rad = deg * Math.PI / 180.0;
            fieldX[i] = (centerX + radius * Math.sin(rad)).toNumber();
            fieldY[i] = (centerY - radius * Math.cos(rad)).toNumber();
        }
    }

    // Estremi delle 24 tacche orarie, separati per spessore così che in fase di
    // disegno servano solo due setColor/setPenWidth invece di 24.
    hidden function buildHourTicks() {
        ticksThin = new [4 * 20];
        ticksCardinal = new [4 * 4];
        var ti = 0;
        var ci = 0;
        var outerR = centerX - 6;
        for (var i = 0; i < 24; i++) {
            var rad = i * 15.0 * Math.PI / 180.0;
            var sinA = Math.sin(rad);
            var cosA = Math.cos(rad);
            var isCardinal = (i % 6 == 0);
            var innerR = isCardinal ? (centerX - 17) : (centerX - 11);
            var x1 = (centerX + outerR * sinA).toNumber();
            var y1 = (centerY - outerR * cosA).toNumber();
            var x2 = (centerX + innerR * sinA).toNumber();
            var y2 = (centerY - innerR * cosA).toNumber();
            if (isCardinal) {
                ticksCardinal[ci]     = x1;
                ticksCardinal[ci + 1] = y1;
                ticksCardinal[ci + 2] = x2;
                ticksCardinal[ci + 3] = y2;
                ci += 4;
            } else {
                ticksThin[ti]     = x1;
                ticksThin[ti + 1] = y1;
                ticksThin[ti + 2] = x2;
                ticksThin[ti + 3] = y2;
                ti += 4;
            }
        }
    }

    // Le stringhe visibili all'utente stanno in resources/strings/strings.xml:
    // si caricano una volta sola in onLayout, mai in onUpdate.
    hidden function loadStrings() {
        dayNames = [
            Ui.loadResource(Rez.Strings.DaySun),
            Ui.loadResource(Rez.Strings.DayMon),
            Ui.loadResource(Rez.Strings.DayTue),
            Ui.loadResource(Rez.Strings.DayWed),
            Ui.loadResource(Rez.Strings.DayThu),
            Ui.loadResource(Rez.Strings.DayFri),
            Ui.loadResource(Rez.Strings.DaySat)
        ];
        strDays    = Ui.loadResource(Rez.Strings.DaysLabel);
        strNoTime  = Ui.loadResource(Rez.Strings.NoData);
        strNoValue = Ui.loadResource(Rez.Strings.NoValue);
    }

    // onShow: la watchface torna visibile → invalidiamo la cache del sole così
    // che al primo update venga rigenerata (i dati potrebbero essere cambiati).
    function onShow() {
        lastSunCalcDay = -1;
        lastSunAttemptMin = -1;
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

        // Snapshot dei dati di sistema: ogni chiamata a queste API ha un costo
        // non trascurabile, quindi si legge UNA sola volta per frame e si passa
        // il risultato ai singoli campi (prima erano fino a 7 letture ciascuna).
        var settings = Sys.getDeviceSettings();
        var clock    = Sys.getClockTime();
        var actMon   = ActivityMonitor.getInfo();
        var activity = Activity.getActivityInfo();
        var stats    = Sys.getSystemStats();
        var weather  = readWeather();

        // Un solo Gregorian.info per frame: la chiave di giornata serve a sole,
        // luna e stringa della data.
        var now     = Time.now();
        var dateInfo = Gregorian.info(now, Time.FORMAT_SHORT);
        var dayKey   = dateInfo.year * 10000 + dateInfo.month * 100 + dateInfo.day;

        // Cambio 12/24h dalle impostazioni: invalida le stringhe orarie in cache.
        var is24 = settings.is24Hour;
        if (lastIs24 != is24) {
            lastIs24 = is24;
            refreshSunStrings(is24);
        }

        // Dati semi-statici, ricalcolati solo al cambio giorno.
        ensureSunData(dayKey, now, weather, is24, clock);
        ensureMoonData(dayKey, now);
        ensureDateString(dayKey, dateInfo);

        // Antialiasing: migliora nettamente archi, poligoni e linee oblique
        // (anello, lancetta dell'ora, icone vettoriali). Disponibile da CIQ 3.2.
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        // Layer 0: sfondo (anello fasi del giorno + tacche orarie)
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        drawPhaseRing(dc, cx, cy);

        // Layer 1: indicatore dell'ora corrente (dinamico, cambia ogni minuto)
        drawNowIndicator(dc, cx, cy, ringRadius, clock);

        // Layer 2: orario, separatore blu, data
        drawCenterTime(dc, cx, cy, clock, is24);
        dc.setColor(0x0066CC, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cx - 38, cy + 19, cx + 38, cy + 19);
        drawCenterDate(dc, cx, cy);

        // Secondi correnti (0–59): mostrati come testo SOPRA l'orario, con font
        // più piccolo (FONT_MEDIUM) rispetto al FONT_NUMBER_MEDIUM dell'orario.
        drawCenterSeconds(dc, cx, cy, clock);

        // Icona telefono connesso (sopra l'orario); nessun indicatore se non connesso
        drawPhoneIcon(dc, cx, cy, settings);

        // Fase lunare (glifo vettoriale sotto la data)
        drawMoonPhase(dc);

        // Layer 3: campi dati radiali (slot da 30°, posizionati tra le tacche,
        // con coordinate precalcolate in onLayout)
        var statute = (settings.temperatureUnits == Sys.UNIT_STATUTE);
        drawFieldWeather     (dc, fieldX[0], fieldY[0], weather, statute);  // 1-2
        drawFieldTempRange   (dc, fieldX[1], fieldY[1], weather, statute);  // 2-3
        drawFieldAltitude    (dc, fieldX[2], fieldY[2], activity, settings);// 3-4
        drawFieldSteps       (dc, fieldX[3], fieldY[3], actMon);            // 4-5
        drawFieldSunset      (dc, fieldX[4], fieldY[4]);                    // 5-6
        drawFieldSun         (dc, fieldX[5], fieldY[5], now);               // 6-7
        drawFieldFloors      (dc, fieldX[6], fieldY[6], actMon);            // 7-8
        drawFieldBatteryDays (dc, fieldX[7], fieldY[7], stats);             // 8-9
        drawFieldBattery     (dc, fieldX[8], fieldY[8], stats);             // 9-10
        drawFieldHR          (dc, fieldX[9], fieldY[9], activity);          // 10-11
    }

    // Condizioni meteo lette una sola volta per frame (prima: 3 chiamate).
    hidden function readWeather() {
        if (!(Toybox has :Weather)) { return null; }
        return Weather.getCurrentConditions();
    }

    // ----- Anello 24h delle fasi del giorno (cerchio esterno unico) -----

    hidden function drawPhaseRing(dc, cx, cy) {
        var r = ringRadius;
        dc.setPenWidth(5);

        if (cachedPhaseArcs == null) {
            // Nessun dato di posizione: anello neutro monocromatico.
            dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r);
            drawHourTicks(dc);
            return;
        }

        for (var i = 0; i < cachedPhaseArcs.size(); i++) {
            var arc = cachedPhaseArcs[i];
            dc.setColor(arc[2], Gfx.COLOR_TRANSPARENT);
            dc.drawArc(cx, cy, r, Gfx.ARC_CLOCKWISE, arc[0], arc[1]);
        }

        // Tacche orarie bianche sopra i colori (l'indicatore dell'ora corrente
        // è dinamico e viene disegnato dopo, in onUpdate)
        drawHourTicks(dc);
    }

    // Disegna le tacche precalcolate: due soli cambi di stato del dc invece di
    // uno per tacca.
    hidden function drawHourTicks(dc) {
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        for (var i = 0; i < ticksThin.size(); i += 4) {
            dc.drawLine(ticksThin[i], ticksThin[i + 1],
                        ticksThin[i + 2], ticksThin[i + 3]);
        }
        dc.setPenWidth(2);
        for (var j = 0; j < ticksCardinal.size(); j += 4) {
            dc.drawLine(ticksCardinal[j], ticksCardinal[j + 1],
                        ticksCardinal[j + 2], ticksCardinal[j + 3]);
        }
        dc.setPenWidth(1);
    }

    // Costruisce l'elenco degli archi dell'anello (una volta al giorno) a
    // partire dai minuti locali di crepuscolo civile, alba e tramonto.
    hidden function buildPhaseArcs() {
        if (cachedSunrise == null || cachedSunset == null) {
            cachedPhaseArcs = null;
            return;
        }

        var sr   = momentToLocalMin(cachedSunrise);
        var ss   = momentToLocalMin(cachedSunset);
        var dawn = (cachedCivilDawn != null) ? momentToLocalMin(cachedCivilDawn) : sr;
        var dusk = (cachedCivilDusk != null) ? momentToLocalMin(cachedCivilDusk) : ss;

        var segments = [
            [0,    dawn, Gfx.COLOR_BLUE],
            [dawn, sr,   Gfx.COLOR_RED],
            [sr,   ss,   Gfx.COLOR_YELLOW],
            [ss,   dusk, Gfx.COLOR_RED],
            [dusk, 1440, Gfx.COLOR_BLUE]
        ];

        var arcs = [];
        for (var i = 0; i < segments.size(); i++) {
            var s = segments[i];
            if (s[1] - s[0] < 1) { continue; }
            arcs.add([
                normDeg(90.0 - (s[0] / 4.0)),
                normDeg(90.0 - (s[1] / 4.0)),
                s[2]
            ]);
        }
        cachedPhaseArcs = arcs;
    }

    hidden function drawNowIndicator(dc, cx, cy, radius, clock) {
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

    hidden function drawCenterTime(dc, cx, cy, clock, is24) {
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

    // Secondi sopra l'orario, font più piccolo dell'orario.
    // Mostrati esclusivamente quando l'orologio è sveglio (isAwake): in
    // low-power mode onUpdate viene chiamato al più una volta al minuto, quindi
    // i secondi sarebbero un valore fermo e fuorviante → li nascondiamo.
    hidden function drawCenterSeconds(dc, cx, cy, clock) {
        if (!isAwake) { return; }
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy - 50, Gfx.FONT_MEDIUM, clock.sec.format("%02d"),
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // La stringa della data cambia una volta al giorno: viene rigenerata solo
    // al cambio giorno invece che a ogni frame.
    hidden function ensureDateString(dayKey, info) {
        if (dayKey == lastDateDay) { return; }
        var dayName = dayNames[info.day_of_week - 1];
        cachedDateStr = Lang.format("$1$ $2$/$3$/$4$", [
            dayName,
            info.day.format("%02d"),
            info.month.format("%02d"),
            (info.year % 100).format("%02d")
        ]);
        lastDateDay = dayKey;
    }

    hidden function drawCenterDate(dc, cx, cy) {
        dc.setColor(0x55BBFF, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + 35, Gfx.FONT_XTINY, cachedDateStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // ----- Campi dati -----

    hidden function drawFieldHR(dc, x, y, activity) {
        var hr = readHeartRate(activity);
        var hrStr = (hr != null) ? hr.toString() : strNoValue;

        drawHeartIcon(dc, x, y - 8, 6);
        drawValue(dc, x, y + 9, hrStr, Gfx.COLOR_WHITE);
    }

    hidden function drawFieldWeather(dc, x, y, weather, statute) {
        if (weather == null) { return; }

        var tempStr = null;
        if (weather.temperature != null) {
            tempStr = toDisplayTemp(weather.temperature, statute) + "°";
        }

        WeatherIcons.draw(dc, x, y - 8, 16, weather.condition);
        if (tempStr != null) {
            drawValue(dc, x, y + 11, tempStr, Gfx.COLOR_WHITE);
        }
    }

    // Minima e massima previste per la giornata corrente (Toybox.Weather),
    // su un'unica riga "min°/max°". Stesso stile icona+valore degli altri campi.
    hidden function drawFieldTempRange(dc, x, y, weather, statute) {
        var hiStr = strNoValue;
        var loStr = strNoValue;
        if (weather != null) {
            if (weather.highTemperature != null) {
                hiStr = toDisplayTemp(weather.highTemperature, statute);
            }
            if (weather.lowTemperature != null) {
                loStr = toDisplayTemp(weather.lowTemperature, statute);
            }
        }
        drawThermometerIcon(dc, x, y - 8, 12);
        drawValue(dc, x, y + 10, loStr + "°/" + hiStr + "°", Gfx.COLOR_WHITE);
    }

    // Converte una temperatura in °C nell'unità impostata sull'orologio.
    hidden function toDisplayTemp(celsius, statute) {
        var t = celsius;
        if (statute) { t = (t * 9.0 / 5.0) + 32.0; }
        return t.toNumber().toString();
    }

    hidden function drawFieldFloors(dc, x, y, info) {
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
        // Obiettivo raggiunto → valore in verde (feedback immediato a colpo d'occhio)
        var color = (floorGoal > 0 && floors >= floorGoal)
            ? Gfx.COLOR_GREEN : Gfx.COLOR_WHITE;
        drawValue(dc, x, y + 9, s, color);
    }

    hidden function drawFieldSun(dc, x, y, now) {
        // La cache di alba/tramonto è aggiornata in onUpdate via ensureSunData()
        var timeStr = strNoTime;
        var nowVal = now.value();
        if (cachedSunriseStr != null && cachedSunrise.value() > nowVal) {
            timeStr = cachedSunriseStr;
        } else if (cachedTomorrowSunriseStr != null) {
            timeStr = cachedTomorrowSunriseStr;
        } else if (cachedSunriseStr != null) {
            timeStr = cachedSunriseStr;
        }

        drawSunHorizonIcon(dc, x, y - 9, 15, Gfx.COLOR_YELLOW, true);
        drawValue(dc, x, y + 9, timeStr, Gfx.COLOR_WHITE);
    }

    hidden function drawFieldSunset(dc, x, y) {
        // La cache di alba/tramonto è aggiornata in onUpdate via ensureSunData()
        var timeStr = (cachedSunsetStr != null) ? cachedSunsetStr : strNoTime;

        drawSunHorizonIcon(dc, x, y - 9, 15, Gfx.COLOR_ORANGE, false);
        drawValue(dc, x, y + 9, timeStr, Gfx.COLOR_WHITE);
    }

    hidden function drawFieldAltitude(dc, x, y, info, settings) {
        var alt = null;
        if (info != null && info has :altitude && info.altitude != null) {
            alt = info.altitude;
        }
        var altStr = strNoValue;
        if (alt != null) {
            var unit = "m";
            if (settings.elevationUnits == Sys.UNIT_STATUTE) {
                alt = alt * 3.28084;
                unit = "ft";
            }
            altStr = alt.toNumber().toString() + unit;
        }
        drawMountainIcon(dc, x, y - 8, 12);
        drawValue(dc, x, y + 9, altStr, Gfx.COLOR_WHITE);
    }

    hidden function drawFieldSteps(dc, x, y, info) {
        var steps = 0;
        var goal = 0;
        if (info != null) {
            if (info.steps != null) { steps = info.steps; }
            if (info.stepGoal != null) { goal = info.stepGoal; }
        }

        drawShoeIcon(dc, x, y - 7, 5);
        // Obiettivo passi raggiunto → valore in verde, come per i piani.
        var color = (goal > 0 && steps >= goal) ? Gfx.COLOR_GREEN : Gfx.COLOR_WHITE;
        drawValue(dc, x, y + 9, steps.toString(), color);
    }

    hidden function drawFieldBattery(dc, x, y, stats) {
        var batt = (stats != null && stats.battery != null) ? stats.battery : 0.0;
        var battInt = batt.toNumber();

        var color = batteryColor(battInt);

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

        // Il valore percentuale segue il colore della carica: rosso/giallo/verde
        // rendono lo stato leggibile anche senza guardare il livello di riempimento.
        drawValue(dc, x, y + 9, battInt.toString() + "%", color);
    }

    hidden function batteryColor(pct) {
        if (pct <= 20) { return Gfx.COLOR_RED; }
        if (pct <= 40) { return Gfx.COLOR_YELLOW; }
        return Gfx.COLOR_GREEN;
    }

    hidden function drawFieldBatteryDays(dc, x, y, stats) {
        var daysStr = strNoValue;
        if (stats != null && (stats has :batteryInDays) && stats.batteryInDays != null) {
            daysStr = stats.batteryInDays.format("%.0f");
        }
        drawValue(dc, x, y - 8, strDays, 0x55BBFF);
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

    hidden function readHeartRate(actInfo) {
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
    // Si tenta, nell'ordine:
    //   1) la località di osservazione del meteo (Toybox.Weather), che segue la
    //      posizione del telefono/orologio (richiede il permesso Positioning);
    //   2) l'ultima posizione nota del GPS (Toybox.Position.getInfo()), che NON
    //      accende il GPS ma restituisce l'ultimo fix disponibile;
    //   3) il valore salvato in Storage da una sessione precedente.
    // La prima posizione valida trovata viene messa in cache in Storage e
    // riutilizzata quando le altre fonti non sono disponibili.
    // NOTA: chiamata solo quando la cache del sole va rigenerata (cambio giorno
    // o assenza di dati), MAI a ogni frame.
    hidden function getLocation(weather) {
        // 1) Località di osservazione del meteo.
        if (weather != null
                && (weather has :observationLocationPosition)
                && weather.observationLocationPosition != null) {
            var loc = degreesIfValid(weather.observationLocationPosition.toDegrees());
            if (loc != null) { return loc; }
        }

        // 2) Ultima posizione nota del GPS (nessun consumo: solo l'ultimo fix).
        if (Toybox has :Position) {
            var info = Position.getInfo();
            if (info != null && info.position != null) {
                var loc = degreesIfValid(info.position.toDegrees());
                if (loc != null) { return loc; }
            }
        }

        // 3) Posizione salvata in precedenza.
        var sLat = App.Storage.getValue("lastLat");
        var sLon = App.Storage.getValue("lastLon");
        if (sLat != null && sLon != null) {
            return [sLat, sLon];
        }
        return null;
    }

    // Valida una coppia [lat, lon] in gradi: ritorna [lat, lon] (salvandola in
    // cache) se è una posizione plausibile, altrimenti null. Scarta il valore
    // (0,0) che le API restituiscono quando non hanno ancora un fix valido.
    hidden function degreesIfValid(deg) {
        if (deg == null || deg.size() < 2) { return null; }
        var lat = deg[0];
        var lon = deg[1];
        if (lat == null || lon == null) { return null; }
        if (lat == 0.0 && lon == 0.0) { return null; }
        saveLocation(lat, lon);
        return [lat, lon];
    }

    hidden function saveLocation(lat, lon) {
        App.Storage.setValue("lastLat", lat);
        App.Storage.setValue("lastLon", lon);
    }

    // Aggiorna la cache di alba/tramonto solo quando serve davvero:
    //  - se i dati del giorno corrente sono già in cache non fa NULLA (nessuna
    //    lettura di meteo, GPS o Storage);
    //  - se manca la posizione riprova al massimo una volta al minuto, per non
    //    interrogare i sensori a ogni frame in attesa della prima sync.
    hidden function ensureSunData(dayKey, now, weather, is24, clock) {
        if (dayKey == lastSunCalcDay) { return; }
        if (clock.min == lastSunAttemptMin) { return; }

        var loc = getLocation(weather);
        if (loc == null) {
            // Posizione non ancora disponibile (es. prima installazione, senza
            // sync con Garmin Connect): riprova al minuto successivo.
            lastSunAttemptMin = clock.min;
            return;
        }
        updateSunCache(loc[0], loc[1], now, dayKey, is24);
    }

    hidden function updateSunCache(lat, lon, now, dayKey, is24) {
        var res = SunCalc.compute(lat, lon, now);
        cachedSunrise = res.get("sunrise");
        cachedSunset  = res.get("sunset");

        var resTw = SunCalc.computeWithZenith(lat, lon, now, SunCalc.ZENITH_CIVIL);
        cachedCivilDawn = resTw.get("sunrise");
        cachedCivilDusk = resTw.get("sunset");

        var tomorrow = now.add(new Time.Duration(86400));
        var resT = SunCalc.compute(lat, lon, tomorrow);
        cachedTomorrowSunrise = resT.get("sunrise");

        // Stringhe e archi dell'anello: derivano dai momenti appena calcolati,
        // quindi si precalcolano qui una volta al giorno.
        refreshSunStrings(is24);
        buildPhaseArcs();

        lastSunCalcDay = dayKey;
    }

    hidden function refreshSunStrings(is24) {
        cachedSunriseStr = (cachedSunrise != null)
            ? formatLocalHM(cachedSunrise, is24) : null;
        cachedSunsetStr = (cachedSunset != null)
            ? formatLocalHM(cachedSunset, is24) : null;
        cachedTomorrowSunriseStr = (cachedTomorrowSunrise != null)
            ? formatLocalHM(cachedTomorrowSunrise, is24) : null;
    }

    hidden function formatLocalHM(moment, is24) {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        var h = info.hour;
        if (is24 == false) {
            h = h % 12;
            if (h == 0) { h = 12; }
        }
        return Lang.format("$1$:$2$", [h.format("%02d"), info.min.format("%02d")]);
    }

    // ----- Fase lunare -----

    // Calcola la fase lunare a partire dalla sola data corrente: puro calcolo
    // astronomico, NESSUN sensore, GPS o chiamata di rete. Eseguito UNA SOLA
    // VOLTA AL GIORNO (guardia sul day-key, come ensureSunData): il risultato,
    // compreso il poligono del glifo, resta in cache e viene riusato a ogni
    // onUpdate senza ricalcolare.
    //
    // FORMULA: si misura l'"età" della luna come tempo trascorso da un
    // novilunio di riferimento noto, riportato nel mese sinodico medio
    // (~29.53 giorni). La frazione del ciclo (0..1) dà fase e illuminazione.
    hidden function ensureMoonData(dayKey, now) {
        if (dayKey == lastMoonCalcDay) { return; }

        // Giorni trascorsi dal novilunio di riferimento (entrambi in UTC).
        var elapsedDays = (now.value() - REF_NEW_MOON_EPOCH) / 86400.0;

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

        buildMoonPolygon();
        lastMoonCalcDay = dayKey;
    }

    // Costruisce il poligono della regione illuminata: si scende lungo il limbo
    // circolare e si risale lungo il terminatore (semi-ellisse di semilarghezza
    // k volte quella del limbo a ciascuna quota). Dipende solo da dati che
    // cambiano una volta al giorno → si calcola qui, non a ogni frame.
    //
    // POSIZIONE E DIMENSIONE: per spostare/ridimensionare l'icona modifica
    // "mx"/"my" (centro) e "R" (raggio) qui sotto.
    hidden function buildMoonPolygon() {
        var mx = centerX;          // centro X: colonna centrale
        var my = centerY + 62;     // centro Y: spazio libero sotto la data
        var R  = 13;               // raggio del disco lunare

        var f = cachedMoonFraction;
        // k: posizione orizzontale del terminatore relativa al limbo (-1..1).
        //   f=0  → k=1  (terminatore sul limbo: nessuna porzione illuminata)
        //   f=.5 → k=0  (terminatore verticale: mezzo disco illuminato)
        //   f=1  → k=-1 (terminatore sul limbo opposto: disco pieno)
        var k = 1.0 - 2.0 * f;
        var sign = cachedMoonWaxing ? 1.0 : -1.0;   // crescente → lato destro

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
        cachedMoonPoly = pts;
    }

    // Disegna il glifo della luna nella fase corrente: disco in ombra +
    // poligono illuminato già pronto in cache (nessun calcolo per frame).
    hidden function drawMoonPhase(dc) {
        if (cachedMoonPoly == null) { return; }
        var mx = centerX;
        var my = centerY + 62;
        var R  = 13;

        // Disco in ombra + contorno (sempre visibile, anche al novilunio).
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_BLACK);
        dc.fillCircle(mx, my, R);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(mx, my, R);

        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(cachedMoonPoly);
    }

    // ----- Icona telefono connesso -----

    // Disegna un'icona "smartphone" vettoriale (nessuna PNG) sopra l'orario,
    // SOLO quando il telefono è connesso. Quando non è connesso non viene
    // mostrato alcun indicatore.
    hidden function drawPhoneIcon(dc, cx, cy, settings) {
        var connected = (settings has :phoneConnected)
            ? (settings.phoneConnected == true) : false;
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
