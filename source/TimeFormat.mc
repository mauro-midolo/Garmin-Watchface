// Conversione dell'ora nel formato impostato sull'orologio, condivisa da
// orario centrale e orari di alba/tramonto.
module TimeFormat {
    function displayHour(hour, is24) {
        if (is24) { return hour; }
        var h = hour % 12;
        return (h == 0) ? 12 : h;
    }
}
