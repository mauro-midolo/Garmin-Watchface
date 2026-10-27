using Toybox.Application as App;
using Toybox.Lang;
using Toybox.Position;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Alba, tramonto e crepuscolo civile del giorno corrente, con la posizione da
// cui vengono calcolati e i dati derivati (stringhe formattate, archi
// dell'anello 24h).
//
// I momenti astronomici cambiano una volta al giorno: si ricalcolano solo al
// cambio giorno. Vengono messe in cache anche le stringhe già formattate e gli
// archi dell'anello, per non rifare Gregorian.info/Lang.format e la conversione
// in gradi a ogni frame.
class SunData {

    hidden var lastDay = -1;
    hidden var lastAttemptMin = -1;

    hidden var sunrise = null;
    hidden var sunset = null;
    hidden var tomorrowSunrise = null;
    hidden var civilDawn = null;
    hidden var civilDusk = null;

    hidden var sunriseStr = null;
    hidden var sunsetStr = null;
    hidden var tomorrowSunriseStr = null;

    // Archi dell'anello 24h già convertiti in gradi: [ [gradiA, gradiB, colore], ... ]
    // null finché la posizione non è nota.
    hidden var phaseArcs = null;

    // Latitudine dell'ultima posizione usata (null = sconosciuta).
    hidden var latitude = null;

    function initialize() {
    }

    // Forza il ricalcolo al prossimo ensure() (es. la watchface torna visibile
    // e i dati potrebbero essere cambiati).
    function invalidate() {
        lastDay = -1;
        lastAttemptMin = -1;
    }

    function getPhaseArcs() { return phaseArcs; }
    function getSunsetStr() { return sunsetStr; }

    // true se la posizione nota è nell'emisfero sud.
    function isSouthern() {
        return latitude != null && latitude < 0.0;
    }

    // Prossima alba: quella di oggi se non è ancora avvenuta, altrimenti
    // quella di domani. null se non disponibile.
    function getNextSunriseStr(now) {
        if (sunriseStr != null && sunrise.value() > now.value()) {
            return sunriseStr;
        }
        if (tomorrowSunriseStr != null) { return tomorrowSunriseStr; }
        return sunriseStr;
    }

    // Aggiorna la cache solo quando serve davvero:
    //  - se i dati del giorno corrente sono già in cache non fa NULLA (nessuna
    //    lettura di meteo, GPS o Storage);
    //  - se manca la posizione riprova al massimo una volta al minuto, per non
    //    interrogare i sensori a ogni frame in attesa della prima sync.
    function ensure(dayKey, now, weather, is24, clock) {
        if (dayKey == lastDay) { return; }
        if (clock.min == lastAttemptMin) { return; }

        var loc = getLocation(weather);
        if (loc == null) {
            // Posizione non ancora disponibile (es. prima installazione, senza
            // sync con Garmin Connect): riprova al minuto successivo.
            lastAttemptMin = clock.min;
            return;
        }
        compute(loc[0], loc[1], now, is24);
        lastDay = dayKey;
    }

    // Rigenera le stringhe orarie (es. dopo il cambio 12/24h).
    function refreshStrings(is24) {
        sunriseStr = (sunrise != null) ? formatLocalHM(sunrise, is24) : null;
        sunsetStr  = (sunset != null)  ? formatLocalHM(sunset, is24)  : null;
        tomorrowSunriseStr = (tomorrowSunrise != null)
            ? formatLocalHM(tomorrowSunrise, is24) : null;
    }

    hidden function compute(lat, lon, now, is24) {
        latitude = lat;

        var res = SunCalc.compute(lat, lon, now);
        sunrise = res.get("sunrise");
        sunset  = res.get("sunset");

        var resTw = SunCalc.computeWithZenith(lat, lon, now, SunCalc.ZENITH_CIVIL);
        civilDawn = resTw.get("sunrise");
        civilDusk = resTw.get("sunset");

        var tomorrow = now.add(new Time.Duration(86400));
        var resT = SunCalc.compute(lat, lon, tomorrow);
        tomorrowSunrise = resT.get("sunrise");

        // Stringhe e archi dell'anello: derivano dai momenti appena calcolati,
        // quindi si precalcolano qui una volta al giorno.
        refreshStrings(is24);
        buildPhaseArcs();
    }

    // Costruisce l'elenco degli archi dell'anello a partire dai minuti locali
    // di crepuscolo civile, alba e tramonto.
    hidden function buildPhaseArcs() {
        if (sunrise == null || sunset == null) {
            phaseArcs = null;
            return;
        }

        var sr   = momentToLocalMin(sunrise);
        var ss   = momentToLocalMin(sunset);
        var dawn = (civilDawn != null) ? momentToLocalMin(civilDawn) : sr;
        var dusk = (civilDusk != null) ? momentToLocalMin(civilDusk) : ss;

        var segments = [
            [0,    dawn, Palette.RING_NIGHT],
            [dawn, sr,   Palette.RING_TWILIGHT],
            [sr,   ss,   Palette.RING_DAY],
            [ss,   dusk, Palette.RING_TWILIGHT],
            [dusk, 1440, Palette.RING_NIGHT]
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
        phaseArcs = arcs;
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
    // NOTA: chiamata solo quando la cache va rigenerata (cambio giorno o
    // assenza di dati), MAI a ogni frame.
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
        App.Storage.setValue("lastLat", lat);
        App.Storage.setValue("lastLon", lon);
        return [lat, lon];
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

    hidden function formatLocalHM(moment, is24) {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return Lang.format("$1$:$2$", [
            TimeFormat.displayHour(info.hour, is24).format("%02d"),
            info.min.format("%02d")
        ]);
    }
}
