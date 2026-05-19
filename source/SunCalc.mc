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

    // Calcola alba e tramonto per latitudine, longitudine e moment dato.
    // Ritorna { :sunrise => Moment|null, :sunset => Moment|null }
    function compute(lat, lon, moment) {
        var info = Gregorian.utcInfo(moment, Time.FORMAT_SHORT);
        var year = info.year;
        var month = info.month;
        var day = info.day;

        // Day of year
        var n = dayOfYear(year, month, day);

        // Approssimazione frazione di giorno corrente in UTC
        // Solar noon approx
        var lngHour = lon / 15.0;
        var results = {};
        var keys = [ { :which => "sunrise", :t => 6.0 }, { :which => "sunset", :t => 18.0 } ];

        for (var i = 0; i < keys.size(); i++) {
            var which = keys[i][:which];
            var t = n + ((keys[i][:t] - lngHour) / 24.0);

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
            var zenith = 90.833; // official sunrise/sunset
            var cosH = (cosDeg(zenith) - (sinDec * sinDeg(lat))) / (cosDec * cosDeg(lat));

            if (cosH > 1.0 || cosH < -1.0) {
                results.put(which, null);
                continue;
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

            // Build Moment for that day in UTC
            var hours = Math.floor(UT).toNumber();
            var minutes = Math.floor((UT - hours) * 60.0).toNumber();
            var seconds = Math.floor((((UT - hours) * 60.0) - minutes) * 60.0).toNumber();

            var opts = {
                :year => year, :month => month, :day => day,
                :hour => hours, :minute => minutes, :second => seconds
            };
            var m = Gregorian.moment(opts);
            results.put(which, m);
        }

        return results;
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
