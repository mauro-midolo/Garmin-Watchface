using Toybox.Graphics as Gfx;
using Toybox.Math;
using Toybox.Weather;

// Disegna icone meteo semplici a partire dalle condizioni di Toybox.Weather.
// Tutte le icone sono disegnate dentro a un riquadro centrato in (cx, cy)
// di dimensione approssimativa "size" (consigliato 22-28).
module WeatherIcons {

    enum {
        ICON_SUNNY,
        ICON_PARTLY_CLOUDY,
        ICON_CLOUDY,
        ICON_RAIN,
        ICON_SNOW,
        ICON_THUNDER,
        ICON_FOG,
        ICON_WINDY,
        ICON_UNKNOWN
    }

    // Mappa una Weather.CONDITION_* a una famiglia di icona.
    function fromCondition(c) {
        if (c == null) { return ICON_UNKNOWN; }

        if (c == Weather.CONDITION_CLEAR
                || c == Weather.CONDITION_FAIR
                || c == Weather.CONDITION_MOSTLY_CLEAR) {
            return ICON_SUNNY;
        }

        if (c == Weather.CONDITION_PARTLY_CLOUDY
                || c == Weather.CONDITION_PARTLY_CLEAR
                || c == Weather.CONDITION_THIN_CLOUDS) {
            return ICON_PARTLY_CLOUDY;
        }

        if (c == Weather.CONDITION_MOSTLY_CLOUDY
                || c == Weather.CONDITION_CLOUDY) {
            return ICON_CLOUDY;
        }

        if (c == Weather.CONDITION_RAIN
                || c == Weather.CONDITION_LIGHT_RAIN
                || c == Weather.CONDITION_HEAVY_RAIN
                || c == Weather.CONDITION_SCATTERED_SHOWERS
                || c == Weather.CONDITION_SHOWERS
                || c == Weather.CONDITION_LIGHT_SHOWERS
                || c == Weather.CONDITION_HEAVY_SHOWERS
                || c == Weather.CONDITION_DRIZZLE
                || c == Weather.CONDITION_UNKNOWN_PRECIPITATION) {
            return ICON_RAIN;
        }

        if (c == Weather.CONDITION_SNOW
                || c == Weather.CONDITION_LIGHT_SNOW
                || c == Weather.CONDITION_HEAVY_SNOW
                || c == Weather.CONDITION_LIGHT_RAIN_SNOW
                || c == Weather.CONDITION_HEAVY_RAIN_SNOW
                || c == Weather.CONDITION_RAIN_SNOW
                || c == Weather.CONDITION_WINTRY_MIX
                || c == Weather.CONDITION_HAIL
                || c == Weather.CONDITION_FLURRIES
                || c == Weather.CONDITION_ICE_SNOW) {
            return ICON_SNOW;
        }

        if (c == Weather.CONDITION_THUNDERSTORMS
                || c == Weather.CONDITION_SCATTERED_THUNDERSTORMS) {
            return ICON_THUNDER;
        }

        if (c == Weather.CONDITION_FOG
                || c == Weather.CONDITION_HAZY
                || c == Weather.CONDITION_MIST
                || c == Weather.CONDITION_HAZE
                || c == Weather.CONDITION_SMOKE
                || c == Weather.CONDITION_SAND
                || c == Weather.CONDITION_DUST
                || c == Weather.CONDITION_VOLCANIC_ASH) {
            return ICON_FOG;
        }

        if (c == Weather.CONDITION_WINDY
                || c == Weather.CONDITION_SQUALL
                || c == Weather.CONDITION_SANDSTORM
                || c == Weather.CONDITION_TORNADO
                || c == Weather.CONDITION_HURRICANE
                || c == Weather.CONDITION_TROPICAL_STORM) {
            return ICON_WINDY;
        }

        return ICON_UNKNOWN;
    }

    function draw(dc, cx, cy, size, condition) {
        var icon = fromCondition(condition);
        if (icon == ICON_SUNNY)             { drawSun(dc, cx, cy, size); }
        else if (icon == ICON_PARTLY_CLOUDY) { drawSunCloud(dc, cx, cy, size); }
        else if (icon == ICON_CLOUDY)        { drawCloud(dc, cx, cy, size, Gfx.COLOR_LT_GRAY); }
        else if (icon == ICON_RAIN)          { drawRain(dc, cx, cy, size); }
        else if (icon == ICON_SNOW)          { drawSnow(dc, cx, cy, size); }
        else if (icon == ICON_THUNDER)       { drawThunder(dc, cx, cy, size); }
        else if (icon == ICON_FOG)           { drawFog(dc, cx, cy, size); }
        else if (icon == ICON_WINDY)         { drawWind(dc, cx, cy, size); }
        else                                  { drawUnknown(dc, cx, cy, size); }
    }

    hidden function drawSun(dc, cx, cy, size) {
        var r = size / 4;
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(cx, cy, r);
        dc.setPenWidth(2);
        var outer = (size / 2) - 1;
        for (var i = 0; i < 8; i++) {
            var a = i * Math.PI / 4.0;
            var x1 = cx + (r + 2) * Math.cos(a);
            var y1 = cy + (r + 2) * Math.sin(a);
            var x2 = cx + outer * Math.cos(a);
            var y2 = cy + outer * Math.sin(a);
            dc.drawLine(x1, y1, x2, y2);
        }
        dc.setPenWidth(1);
    }

    hidden function drawCloud(dc, cx, cy, size, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        var r1 = size / 4;
        var r2 = size / 3;
        var r3 = size / 4;
        dc.fillCircle(cx - r2, cy + 1, r1);
        dc.fillCircle(cx,      cy - 2, r2);
        dc.fillCircle(cx + r2, cy + 1, r3);
        dc.fillRectangle(cx - r2, cy, 2 * r2, r1 + 1);
    }

    hidden function drawSunCloud(dc, cx, cy, size) {
        drawSun(dc, cx - size / 5, cy - size / 5, size * 3 / 4);
        drawCloud(dc, cx + size / 8, cy + size / 8, size * 3 / 4, Gfx.COLOR_LT_GRAY);
    }

    hidden function drawRain(dc, cx, cy, size) {
        drawCloud(dc, cx, cy - size / 6, size, Gfx.COLOR_LT_GRAY);
        dc.setColor(Gfx.COLOR_BLUE, Gfx.COLOR_TRANSPARENT);
        var dy = cy + size / 4;
        var offsets = [-size / 4, 0, size / 4];
        for (var i = 0; i < offsets.size(); i++) {
            var x = cx + offsets[i];
            dc.fillCircle(x, dy + 2, 2);
            dc.setPenWidth(2);
            dc.drawLine(x, dy - 2, x, dy + 2);
            dc.setPenWidth(1);
        }
    }

    hidden function drawSnow(dc, cx, cy, size) {
        drawCloud(dc, cx, cy - size / 6, size, Gfx.COLOR_LT_GRAY);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        var dy = cy + size / 4 + 1;
        var offsets = [-size / 4, 0, size / 4];
        for (var i = 0; i < offsets.size(); i++) {
            var x = cx + offsets[i];
            dc.fillCircle(x, dy, 2);
        }
    }

    hidden function drawThunder(dc, cx, cy, size) {
        drawCloud(dc, cx, cy - size / 6, size, Gfx.COLOR_DK_GRAY);
        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_YELLOW);
        var pts = [
            [cx,     cy + 1],
            [cx + 4, cy + 1],
            [cx + 1, cy + size / 3],
            [cx + 6, cy + size / 3 - 2],
            [cx - 2, cy + size / 2 + 1],
            [cx + 1, cy + size / 4],
            [cx - 3, cy + size / 4]
        ];
        dc.fillPolygon(pts);
    }

    hidden function drawFog(dc, cx, cy, size) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var step = size / 5;
        var half = size / 2;
        for (var i = -2; i <= 2; i++) {
            var y = cy + i * step;
            dc.drawLine(cx - half, y, cx + half, y);
        }
        dc.setPenWidth(1);
    }

    hidden function drawWind(dc, cx, cy, size) {
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        var half = size / 2;
        dc.drawLine(cx - half, cy - size / 4, cx + half - 3, cy - size / 4);
        dc.drawLine(cx - half, cy,             cx + half,     cy);
        dc.drawLine(cx - half, cy + size / 4, cx + half - 6, cy + size / 4);
        dc.setPenWidth(1);
    }

    hidden function drawUnknown(dc, cx, cy, size) {
        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.drawText(cx, cy, Gfx.FONT_TINY, "?",
            Gfx.TEXT_JUSTIFY_CENTER | Gfx.TEXT_JUSTIFY_VCENTER);
    }
}
