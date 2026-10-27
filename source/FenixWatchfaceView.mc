using Toybox.WatchUi as Ui;
using Toybox.Graphics as Gfx;
using Toybox.System as Sys;
using Toybox.Lang;
using Toybox.Math;
using Toybox.Time;
using Toybox.Time.Gregorian;
using Toybox.ActivityMonitor;
using Toybox.Activity;
using Toybox.Weather;

class FenixWatchfaceView extends Ui.WatchFace {

    // Assegnazione dei campi agli slot radiali: slot 0 a 45°, poi in senso
    // orario ogni 30° (vedi Layout). L'ordine di fieldRenderers in onLayout
    // segue questo enum. I campi con i valori più lunghi (min/max, batteria
    // con giorni) stanno nei due slot in alto, dove il quadrante è più largo
    // all'altezza del testo.
    enum {
        SLOT_TEMP_RANGE,     //  45°
        SLOT_WEATHER,        //  75°
        SLOT_ALTITUDE,       // 105°
        SLOT_STEPS,          // 135°
        SLOT_SUNSET,         // 165°
        SLOT_SUNRISE,        // 195°
        SLOT_FLOORS,         // 225°
        SLOT_NOTIFICATIONS,  // 255°
        SLOT_HR,             // 285°
        SLOT_BATTERY         // 315°
    }

    // Stato di alimentazione: true quando l'orologio è "sveglio" e onUpdate
    // viene chiamato ogni secondo (high-power mode); false in low-power mode,
    // quando onUpdate è chiamato al più una volta al minuto. I secondi vengono
    // mostrati solo quando isAwake è true, cioè quando sono effettivamente
    // aggiornati in tempo reale.
    hidden var isAwake = true;

    // Dati semi-statici, ricalcolati al più una volta al giorno.
    hidden var sun;    // alba/tramonto e anello 24h
    hidden var moon;   // fase lunare

    // Cache della stringa di data: cambia una volta al giorno.
    hidden var lastDateDay = -1;
    hidden var cachedDateStr = "";

    // Formato orario corrente (12/24h): se l'utente lo cambia dalle impostazioni
    // le stringhe già formattate in cache vanno rigenerate.
    hidden var lastIs24 = null;

    // Geometria dello schermo, calcolata una sola volta in onLayout
    hidden var centerX = 0;
    hidden var centerY = 0;
    hidden var ringRadius = 0;

    // Geometria precalcolata in onLayout: posizioni dei campi, tacche orarie e
    // icone sono costanti, quindi seno/coseno si calcolano una volta sola
    // invece che a ogni frame.
    hidden var fieldX = null;         // ascisse dei 10 slot radiali
    hidden var fieldY = null;         // ordinate dei 10 slot radiali
    hidden var fieldMaxW = null;      // larghezza massima del valore di ogni slot
    hidden var ticksThin = null;      // [x1,y1,x2,y2, ...] tacche normali
    hidden var ticksCardinal = null;  // [x1,y1,x2,y2, ...] tacche cardinali
    hidden var timeFont = Gfx.FONT_NUMBER_MEDIUM;

    hidden var iconHeart = null;
    hidden var iconShoe = null;
    hidden var iconMountain = null;
    hidden var iconThermometer = null;
    hidden var iconSunrise = null;
    hidden var iconSunset = null;

    // Funzioni di disegno dei campi, una per slot (indice = slot).
    hidden var fieldRenderers = null;

    // Snapshot dei dati di sistema del frame corrente, letto una volta sola in
    // onUpdate e usato dai singoli campi.
    hidden var frameSettings = null;
    hidden var frameActMon = null;
    hidden var frameActivity = null;
    hidden var frameStats = null;
    hidden var frameWeather = null;
    hidden var frameNow = null;

    // Stringhe localizzate, caricate una volta sola da resources/strings.
    hidden var dayNames = null;
    hidden var strNoTime = "--:--";
    hidden var strNoValue = "--";
    hidden var strMeters = "m";
    hidden var strFeet = "ft";
    hidden var strPercent = "%";
    hidden var strDegree = "°";
    hidden var strDays = "g";

    function initialize() {
        WatchFace.initialize();
        sun = new SunData();
    }

    // onLayout: inizializzazione del layout. Eseguito una sola volta: calcola
    // la geometria dello schermo, precalcola le coordinate costanti (campi
    // radiali, tacche orarie, icone) e carica le stringhe localizzate.
    function onLayout(dc) {
        centerX = dc.getWidth() / 2;
        centerY = dc.getHeight() / 2;
        ringRadius = centerX - Layout.RING_INSET;

        buildFieldPositions(dc);
        buildHourTicks();
        buildIcons();
        chooseTimeFont(dc);
        loadStrings();

        moon = new MoonPhase(centerX, centerY + Layout.MOON_DY, Layout.MOON_R);

        fieldRenderers = [
            method(:drawFieldTempRange),
            method(:drawFieldWeather),
            method(:drawFieldAltitude),
            method(:drawFieldSteps),
            method(:drawFieldSunset),
            method(:drawFieldSunrise),
            method(:drawFieldFloors),
            method(:drawFieldNotifications),
            method(:drawFieldHR),
            method(:drawFieldBattery)
        ];
    }

    // Posizioni dei 10 campi dati (slot da 30° a partire da 45°).
    //
    // Ogni slot parte dal raggio massimo e viene avvicinato al centro, un pixel
    // alla volta, finché icona e valore di riferimento (FIELD_REF_TEXT) stanno
    // dentro al cerchio delle tacche. Così gli slot in diagonale, dove il testo
    // arriva più vicino al bordo, non toccano tacche e anello.
    // Per ogni slot si salva anche la larghezza massima che un valore può avere
    // senza uscire da quel cerchio (usata da drawFitValue).
    hidden function buildFieldPositions(dc) {
        var count = Layout.FIELD_COUNT;
        fieldX = new [count];
        fieldY = new [count];
        fieldMaxW = new [count];

        var halfH = dc.getFontHeight(Gfx.FONT_XTINY) / 2.0;
        var refHalfW = dc.getTextWidthInPixels(Layout.FIELD_REF_TEXT, Gfx.FONT_XTINY) / 2.0;
        var iconHalf = 9.0;
        var limit = (centerX - Layout.TICK_INNER_INSET - Layout.FIELD_TEXT_MARGIN).toFloat();
        var rMax = centerX * Layout.FIELD_RADIUS_MAX;

        for (var i = 0; i < count; i++) {
            var rad = (Layout.FIELD_FIRST_DEG + Layout.FIELD_STEP_DEG * i) * Math.PI / 180.0;
            var sinA = Math.sin(rad);
            var cosA = Math.cos(rad);

            var r = rMax;
            while (r > 0.0) {
                var dx = (r * sinA).abs();
                var dy = -r * cosA;
                var valueReach = boxReach(dx, dy + Layout.VALUE_DY, refHalfW, halfH);
                var iconReach  = boxReach(dx, dy + Layout.ICON_DY, iconHalf, iconHalf);
                if (valueReach <= limit && iconReach <= limit) { break; }
                r -= 1.0;
            }

            // Arrotondamento (non troncamento): slot simmetrici a destra e sinistra.
            fieldX[i] = (centerX + r * sinA + 0.5).toNumber();
            fieldY[i] = (centerY - r * cosA + 0.5).toNumber();

            // Larghezza massima del valore: (|dx| + w/2)² + (|dy| + h/2)² <= limit²
            var vdx = (fieldX[i] - centerX).abs();
            var vdy = (fieldY[i] + Layout.VALUE_DY - centerY).abs() + halfH;
            var d = limit * limit - vdy * vdy;
            var maxHalf = (d > 0.0) ? Math.sqrt(d) - vdx : 0.0;
            fieldMaxW[i] = (maxHalf > 0.0) ? (2 * maxHalf).toNumber() : 0;
        }
    }

    // Distanza dal centro dello schermo del punto più lontano di un box
    // centrato in (dx, dy) rispetto al centro, con semi-dimensioni hw x hh.
    hidden function boxReach(dx, dy, hw, hh) {
        var x = dx.abs() + hw;
        var y = dy.abs() + hh;
        return Math.sqrt(x * x + y * y);
    }

    // Estremi delle 24 tacche orarie, separati per spessore così che in fase di
    // disegno servano solo due setColor/setPenWidth invece di 24.
    hidden function buildHourTicks() {
        ticksThin = new [4 * 20];
        ticksCardinal = new [4 * 4];
        var ti = 0;
        var ci = 0;
        var outerR = centerX - Layout.TICK_OUTER_INSET;
        for (var i = 0; i < 24; i++) {
            var rad = i * 15.0 * Math.PI / 180.0;
            var sinA = Math.sin(rad);
            var cosA = Math.cos(rad);
            var isCardinal = (i % 6 == 0);
            var innerR = centerX - (isCardinal
                ? Layout.TICK_CARDINAL_INSET : Layout.TICK_INNER_INSET);
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

    // Geometria delle icone vettoriali, nella loro posizione definitiva.
    hidden function buildIcons() {
        iconHeart       = Icons.buildHeart(fieldX[SLOT_HR], iconY(SLOT_HR), 6);
        iconShoe        = Icons.buildShoe(fieldX[SLOT_STEPS], iconY(SLOT_STEPS), 5);
        iconMountain    = Icons.buildMountain(fieldX[SLOT_ALTITUDE], iconY(SLOT_ALTITUDE), 12);
        iconThermometer = Icons.buildThermometer(fieldX[SLOT_TEMP_RANGE], iconY(SLOT_TEMP_RANGE), 12);
        iconSunrise     = Icons.buildSunHorizon(fieldX[SLOT_SUNRISE], iconY(SLOT_SUNRISE), 15, true);
        iconSunset      = Icons.buildSunHorizon(fieldX[SLOT_SUNSET], iconY(SLOT_SUNSET), 15, false);
    }

    // Orario grande (FONT_NUMBER_HOT) se ci sta tra i campi radiali alla sua
    // altezza, altrimenti FONT_NUMBER_MEDIUM. Verificato una volta sola con le
    // metriche reali del font del device.
    hidden function chooseTimeFont(dc) {
        var hot = Gfx.FONT_NUMBER_HOT;
        var timeY = centerY + Layout.TIME_DY;
        var halfH = dc.getFontHeight(hot) / 2;
        var valueHalfH = dc.getFontHeight(Gfx.FONT_XTINY) / 2;
        var refHalfW = dc.getTextWidthInPixels(Layout.FIELD_REF_TEXT, Gfx.FONT_XTINY) / 2;

        // Semi-larghezza disponibile: fino al bordo interno dei campi che si
        // sovrappongono in verticale all'orario (compreso l'eventuale
        // spostamento verso il centro dei valori lunghi), con 4 px di margine.
        var maxHalf = centerX;
        for (var i = 0; i < Layout.FIELD_COUNT; i++) {
            var vy = fieldY[i] + Layout.VALUE_DY;
            var iy = fieldY[i] + Layout.ICON_DY;
            var overlaps = (vy + valueHalfH > timeY - halfH && vy - valueHalfH < timeY + halfH)
                || (iy + 9 > timeY - halfH && iy - 9 < timeY + halfH);
            if (overlaps) {
                var avail = (fieldX[i] - centerX).abs() - refHalfW
                    - Layout.FIELD_SHIFT_MAX - 4;
                if (avail < maxHalf) { maxHalf = avail; }
            }
        }

        var timeW = dc.getTextWidthInPixels("00:00", hot);
        timeFont = (timeW / 2 <= maxHalf) ? hot : Gfx.FONT_NUMBER_MEDIUM;
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
        strNoTime  = Ui.loadResource(Rez.Strings.NoData);
        strNoValue = Ui.loadResource(Rez.Strings.NoValue);
        strMeters  = Ui.loadResource(Rez.Strings.UnitMeters);
        strFeet    = Ui.loadResource(Rez.Strings.UnitFeet);
        strPercent = Ui.loadResource(Rez.Strings.UnitPercent);
        strDegree  = Ui.loadResource(Rez.Strings.UnitDegree);
        strDays    = Ui.loadResource(Rez.Strings.UnitDays);
    }

    // onShow: la watchface torna visibile → invalidiamo la cache del sole così
    // che al primo update venga rigenerata (i dati potrebbero essere cambiati).
    function onShow() {
        sun.invalidate();
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
        // non trascurabile, quindi si legge UNA sola volta per frame e la
        // usano tutti i campi.
        frameSettings = Sys.getDeviceSettings();
        frameActMon   = ActivityMonitor.getInfo();
        frameActivity = Activity.getActivityInfo();
        frameStats    = Sys.getSystemStats();
        frameWeather  = readWeather();
        var clock = Sys.getClockTime();

        // Un solo Gregorian.info per frame: la chiave di giornata serve a sole,
        // luna e stringa della data.
        frameNow = Time.now();
        var dateInfo = Gregorian.info(frameNow, Time.FORMAT_SHORT);
        var dayKey   = dateInfo.year * 10000 + dateInfo.month * 100 + dateInfo.day;

        // Cambio 12/24h dalle impostazioni: invalida le stringhe orarie in cache.
        var is24 = frameSettings.is24Hour;
        if (lastIs24 != is24) {
            lastIs24 = is24;
            sun.refreshStrings(is24);
        }

        // Dati semi-statici, ricalcolati solo al cambio giorno.
        sun.ensure(dayKey, frameNow, frameWeather, is24, clock);
        moon.update(dayKey, frameNow, sun.isSouthern());
        ensureDateString(dayKey, dateInfo);

        // Antialiasing di archi, poligoni e linee oblique (CIQ >= 3.2). Il
        // display MIP del Fenix 6 Pro non supporta l'alpha blending, quindi
        // l'effetto può essere minimo: la chiamata è comunque innocua.
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }

        // Layer 0: sfondo (anello fasi del giorno + tacche orarie)
        dc.setColor(Gfx.COLOR_BLACK, Gfx.COLOR_BLACK);
        dc.clear();
        drawPhaseRing(dc, cx, cy);

        // Layer 1: indicatore dell'ora corrente (dinamico, cambia ogni minuto)
        drawNowIndicator(dc, cx, cy, ringRadius, clock);

        // Layer 2: colonna centrale, dall'alto: telefono, secondi, orario,
        // separatore, data, luna.
        drawPhoneIcon(dc, cx, cy);
        drawCenterSeconds(dc, cx, cy, clock);
        drawCenterTime(dc, cx, cy, clock, is24);
        dc.setColor(Palette.ACCENT, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawLine(cx - Layout.SEPARATOR_HALF_W, cy + Layout.SEPARATOR_DY,
                    cx + Layout.SEPARATOR_HALF_W, cy + Layout.SEPARATOR_DY);
        drawCenterDate(dc, cx, cy);
        moon.draw(dc);

        // Layer 3: campi dati radiali
        for (var i = 0; i < fieldRenderers.size(); i++) {
            fieldRenderers[i].invoke(dc, i);
        }
    }

    // Condizioni meteo lette una sola volta per frame.
    hidden function readWeather() {
        if (!(Toybox has :Weather)) { return null; }
        return Weather.getCurrentConditions();
    }

    // ----- Anello 24h delle fasi del giorno (cerchio esterno unico) -----

    hidden function drawPhaseRing(dc, cx, cy) {
        var r = ringRadius;
        dc.setPenWidth(Layout.RING_PEN);

        var arcs = sun.getPhaseArcs();
        if (arcs == null) {
            // Nessun dato di posizione: anello neutro monocromatico.
            dc.setColor(Palette.RING_NIGHT, Gfx.COLOR_TRANSPARENT);
            dc.drawCircle(cx, cy, r);
        } else {
            for (var i = 0; i < arcs.size(); i++) {
                var arc = arcs[i];
                dc.setColor(arc[2], Gfx.COLOR_TRANSPARENT);
                dc.drawArc(cx, cy, r, Gfx.ARC_CLOCKWISE, arc[0], arc[1]);
            }
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
        Icons.drawLines(dc, ticksThin);
        dc.setPenWidth(2);
        Icons.drawLines(dc, ticksCardinal);
        dc.setPenWidth(1);
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

    // ----- Centro: telefono, secondi, orario, data -----

    // Icona "smartphone" sopra i secondi, SOLO quando il telefono è connesso.
    // Quando non è connesso non viene mostrato alcun indicatore.
    hidden function drawPhoneIcon(dc, cx, cy) {
        var connected = (frameSettings has :phoneConnected)
            ? (frameSettings.phoneConnected == true) : false;
        if (!connected) { return; }
        Icons.drawPhone(dc, cx, cy + Layout.PHONE_DY, Layout.PHONE_W, Layout.PHONE_H);
    }

    // Secondi sopra l'orario, con un font molto più piccolo dell'orario così
    // che l'ora resti l'elemento dominante.
    // Mostrati esclusivamente quando l'orologio è sveglio (isAwake): in
    // low-power mode onUpdate viene chiamato al più una volta al minuto, quindi
    // i secondi sarebbero un valore fermo e fuorviante → li nascondiamo.
    hidden function drawCenterSeconds(dc, cx, cy, clock) {
        if (!isAwake) { return; }
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + Layout.SECONDS_DY, Gfx.FONT_TINY, clock.sec.format("%02d"),
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    hidden function drawCenterTime(dc, cx, cy, clock, is24) {
        var timeStr = Lang.format("$1$:$2$", [
            TimeFormat.displayHour(clock.hour, is24).format("%02d"),
            clock.min.format("%02d")
        ]);

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + Layout.TIME_DY, timeFont, timeStr,
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
        dc.setColor(Palette.ACCENT_LIGHT, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy + Layout.DATE_DY, Gfx.FONT_XTINY, cachedDateStr,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // ----- Helper dei campi -----

    hidden function iconY(slot) {
        return fieldY[slot] + Layout.ICON_DY;
    }

    // Valore del campo, sotto l'icona: stessa posizione per tutti gli slot.
    hidden function drawFieldValue(dc, slot, text, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(fieldX[slot], fieldY[slot] + Layout.VALUE_DY, Gfx.FONT_XTINY, text,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // Valore che può non entrare nello slot: se è più largo dello spazio verso
    // il bordo si sposta verso il centro (al più FIELD_SHIFT_MAX px) così da
    // non toccare le tacche; se non basta si usa la forma abbreviata (es. senza
    // unità di misura). Solo i campi con valori lunghi pagano la misura del
    // testo, gli altri usano drawFieldValue.
    hidden function drawFitValue(dc, slot, full, short, color) {
        var maxW = fieldMaxW[slot];
        var text = full;
        var w = dc.getTextWidthInPixels(full, Gfx.FONT_XTINY);
        if (w > maxW + 2 * Layout.FIELD_SHIFT_MAX) {
            text = short;
            w = dc.getTextWidthInPixels(short, Gfx.FONT_XTINY);
        }

        var x = fieldX[slot];
        if (w > maxW) {
            var shift = (w - maxW) / 2;
            if (shift > Layout.FIELD_SHIFT_MAX) { shift = Layout.FIELD_SHIFT_MAX; }
            x += (x > centerX) ? -shift : shift;
        }
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.drawText(x, fieldY[slot] + Layout.VALUE_DY, Gfx.FONT_XTINY, text,
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }

    // ----- Campi dati -----
    // Ogni funzione disegna icona e valore di un campo nello slot ricevuto.
    // Sono pubbliche perché vengono invocate tramite fieldRenderers.

    function drawFieldWeather(dc, slot) {
        var weather = frameWeather;
        if (weather == null) { return; }

        WeatherIcons.draw(dc, fieldX[slot], iconY(slot), 16, weather.condition);
        if (weather.temperature != null) {
            drawFieldValue(dc, slot, toDisplayTemp(weather.temperature) + strDegree,
                Gfx.COLOR_WHITE);
        }
    }

    // Minima e massima previste per la giornata corrente (Toybox.Weather),
    // su un'unica riga "min°/max°".
    function drawFieldTempRange(dc, slot) {
        var weather = frameWeather;
        var hiStr = strNoValue;
        var loStr = strNoValue;
        if (weather != null) {
            if (weather.highTemperature != null) {
                hiStr = toDisplayTemp(weather.highTemperature);
            }
            if (weather.lowTemperature != null) {
                loStr = toDisplayTemp(weather.lowTemperature);
            }
        }
        Icons.drawThermometer(dc, iconThermometer);
        drawFitValue(dc, slot,
            loStr + strDegree + "/" + hiStr + strDegree,
            loStr + "/" + hiStr, Gfx.COLOR_WHITE);
    }

    // Converte una temperatura in °C nell'unità impostata sull'orologio.
    hidden function toDisplayTemp(celsius) {
        var t = celsius;
        if (frameSettings.temperatureUnits == Sys.UNIT_STATUTE) {
            t = (t * 9.0 / 5.0) + 32.0;
        }
        return t.toNumber().toString();
    }

    function drawFieldAltitude(dc, slot) {
        var info = frameActivity;
        Icons.drawMountain(dc, iconMountain);
        if (info == null || !(info has :altitude) || info.altitude == null) {
            drawFieldValue(dc, slot, strNoValue, Gfx.COLOR_WHITE);
            return;
        }
        var alt = info.altitude;
        var unit = strMeters;
        if (frameSettings.elevationUnits == Sys.UNIT_STATUTE) {
            alt = alt * 3.28084;
            unit = strFeet;
        }
        var num = alt.toNumber().toString();
        // Senza unità se il valore non entra (es. quote alte in piedi).
        drawFitValue(dc, slot, num + unit, num, Gfx.COLOR_WHITE);
    }

    function drawFieldSteps(dc, slot) {
        var info = frameActMon;
        var steps = 0;
        var goal = 0;
        if (info != null) {
            if (info.steps != null) { steps = info.steps; }
            if (info.stepGoal != null) { goal = info.stepGoal; }
        }

        Icons.drawShoe(dc, iconShoe);
        drawFieldValue(dc, slot, steps.toString(), goalColor(steps, goal));
    }

    function drawFieldSunset(dc, slot) {
        var timeStr = sun.getSunsetStr();
        Icons.drawSunHorizon(dc, iconSunset, Gfx.COLOR_ORANGE);
        drawFieldValue(dc, slot, (timeStr != null) ? timeStr : strNoTime, Gfx.COLOR_WHITE);
    }

    function drawFieldSunrise(dc, slot) {
        var timeStr = sun.getNextSunriseStr(frameNow);
        Icons.drawSunHorizon(dc, iconSunrise, Gfx.COLOR_YELLOW);
        drawFieldValue(dc, slot, (timeStr != null) ? timeStr : strNoTime, Gfx.COLOR_WHITE);
    }

    function drawFieldFloors(dc, slot) {
        var info = frameActMon;
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
        Icons.drawStairs(dc, fieldX[slot], iconY(slot), 11, Palette.ACCENT);
        var s = (floorGoal > 0)
            ? Lang.format("$1$/$2$", [floors, floorGoal])
            : floors.toString();
        drawFieldValue(dc, slot, s, goalColor(floors, floorGoal));
    }

    // Obiettivo raggiunto → valore in verde (feedback immediato a colpo d'occhio).
    hidden function goalColor(value, goal) {
        return (goal > 0 && value >= goal) ? Palette.GOAL : Gfx.COLOR_WHITE;
    }

    function drawFieldNotifications(dc, slot) {
        var count = 0;
        if ((frameSettings has :notificationCount) && frameSettings.notificationCount != null) {
            count = frameSettings.notificationCount;
        }
        // Busta grigia senza notifiche, bianca quando ce ne sono.
        var color = (count > 0) ? Gfx.COLOR_WHITE : Gfx.COLOR_LT_GRAY;
        Icons.drawEnvelope(dc, fieldX[slot], iconY(slot), color);
        drawFieldValue(dc, slot, count.toString(), color);
    }

    // Batteria: percentuale e, se c'è spazio, giorni di autonomia stimati
    // (es. "87% 12g"). Il valore segue il colore della carica: rosso/giallo/
    // verde rendono lo stato leggibile anche senza guardare il riempimento.
    function drawFieldBattery(dc, slot) {
        var stats = frameStats;
        var batt = (stats != null && stats.battery != null) ? stats.battery : 0.0;
        var battInt = batt.toNumber();
        var color = batteryColor(battInt);

        var pctStr = battInt.toString() + strPercent;
        var full = pctStr;
        if (stats != null && (stats has :batteryInDays) && stats.batteryInDays != null) {
            full = pctStr + " " + stats.batteryInDays.format("%.0f") + strDays;
        }

        Icons.drawBattery(dc, fieldX[slot], iconY(slot), battInt, color);
        drawFitValue(dc, slot, full, pctStr, color);
    }

    hidden function batteryColor(pct) {
        if (pct <= 20) { return Gfx.COLOR_RED; }
        if (pct <= 40) { return Gfx.COLOR_YELLOW; }
        return Gfx.COLOR_GREEN;
    }

    function drawFieldHR(dc, slot) {
        var hr = readHeartRate(frameActivity);
        Icons.drawHeart(dc, iconHeart);
        drawFieldValue(dc, slot, (hr != null) ? hr.toString() : strNoValue, Gfx.COLOR_WHITE);
    }

    // Frequenza cardiaca: valore corrente, con fallback all'ultimo campione
    // dello storico.
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
}
