using Toybox.Math;
using Toybox.Time;
using Toybox.Time.Gregorian;

// Calcolo astronomico semplice di alba/tramonto.
// Basato sull'algoritmo NOAA / "Sunrise equation".
// Ritorna i momenti in Time.Moment (UTC).
module SunCalc {

    const PI = Math.PI;
    const RAD = Math.PI / 180.0;
    const DEG = 180.0 / Math.PI;

    // Zenit ufficiale per alba/tramonto (centro del sole a -0.833°).
    const ZENITH_OFFICIAL = 90.833;
    // Zenit del crepuscolo astronomico (sole a -18°): inizio/fine della notte.
    const ZENITH_ASTRONOMICAL = 108.0;

    // Calcola alba e tramonto "ufficiali" per latitudine, longitudine e moment.
    // Ritorna { :sunrise => Moment|null, :sunset => Moment|null }
    function compute(lat, lon, moment) {
        return computeWithZenith(lat, lon, moment, ZENITH_OFFICIAL);
    }

    // Come compute() ma con zenit configurabile. Con ZENITH_ASTRONOMICAL le
    // chiavi "sunrise"/"sunset" rappresentano alba e tramonto astronomici,
    // cioè gli istanti in cui il sole è 18° sotto l'orizzonte.
    function computeWithZenith(lat, lon, moment, zenith) {
        var info = Gregorian.utcInfo(moment, Time.FORMAT_SHORT);
        var year = info.year;
        var month = info.month;
        var day = info.day;

        // Day of year
        var n = dayOfYear(year, month, day);
        var lngHour = lon / 15.0;

        var results = {};
        var keys = [
            { :which => "sunrise", :t => 6.0 },
            { :which => "sunset",  :t => 18.0 }
        ];
        for (var i = 0; i < keys.size(); i++) {
            var which = keys[i][:which];
            var m = eventMoment(
                lat, year, month, day, n, lngHour, which, keys[i][:t], zenith, moment);
            results.put(which, m);
        }
        return results;
    }

    // Istante (Moment, costruito in UTC) di un singolo evento del sole.
    // Ritorna null se l'evento non avviene (es. notte o giorno polare).
    function eventMoment(lat, year, month, day, n, lngHour, which, tApprox, zenith, moment) {
        // Approssimazione frazione di giorno dell'evento in UTC.
        var t = n + ((tApprox - lngHour) / 24.0);

        // Solar mean anomaly
        var M = (0.9856 * t) - 3.289;

        // Sun true longitude
        var L = M + (1.916 * sinDeg(M)) + (0.020 * sinDeg(2.0 * M)) + 282.634;
        L = normalize(L, 360.0);

        // Right ascension
        var RA = atanDeg(0.91764 * tanDeg(L));
        RA = normalize(RA, 360.0);

        // Adjust RA to same quadrant as L
        var Lquad  = (Math.floor(L / 90.0)) * 90.0;
        var RAquad = (Math.floor(RA / 90.0)) * 90.0;
        RA = RA + (Lquad - RAquad);
        RA = RA / 15.0;

        // Sun declination
        var sinDec = 0.39782 * sinDeg(L);
        var cosDec = cosDeg(asinDeg(sinDec));

        // Sun local hour angle
        var cosH = (cosDeg(zenith) - (sinDec * sinDeg(lat))) / (cosDec * cosDeg(lat));
        if (cosH > 1.0 || cosH < -1.0) {
            return null;
        }

        var H;
        if (which.equals("sunrise")) {
            H = 360.0 - acosDeg(cosH);
        } else {
            H = acosDeg(cosH);
        }
        H = H / 15.0;

        // Local mean time
        var T = H + RA - (0.06571 * t) - 6.622;

        // Adjust back to UTC
        var UT = T - lngHour;
        UT = normalize(UT, 24.0);

        // Build Moment in UTC using epoch arithmetic.
        // Gregorian.moment() interprets fields as local time (not UTC), so we
        // compute from the Unix epoch: UTC midnight of the input date + event UT hours.
        var utcMidnight = (moment.value() / 86400) * 86400;
        return new Time.Moment(utcMidnight + (UT * 3600.0).toNumber());
    }

    function dayOfYear(year, month, day) {
        var daysInMonth = [31,28,31,30,31,30,31,31,30,31,30,31];
        if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) {
            daysInMonth[1] = 29;
        }
        var n = day;
        for (var i = 0; i < month - 1; i++) {
            n += daysInMonth[i];
        }
        return n;
    }

    function normalize(v, max) {
        while (v < 0) { v += max; }
        while (v >= max) { v -= max; }
        return v;
    }

    function sinDeg(d) { return Math.sin(d * RAD); }
    function cosDeg(d) { return Math.cos(d * RAD); }
    function tanDeg(d) { return Math.tan(d * RAD); }
    function asinDeg(v) { return Math.asin(v) * DEG; }
    function acosDeg(v) { return Math.acos(v) * DEG; }
    function atanDeg(v) { return Math.atan(v) * DEG; }
}
