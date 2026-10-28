using Toybox.Graphics as Gfx;
using Toybox.Math;

// Icone vettoriali dei campi dati e della colonna centrale (nessuna PNG).
//
// Le posizioni delle icone sono fisse, quindi le icone con geometria non banale
// (poligoni, raggi) sono divise in due funzioni:
//   - build*() calcola i punti assoluti UNA volta sola, in onLayout;
//   - draw*()  li disegna a ogni frame, senza trigonometria né calcoli.
// Le icone fatte solo di rettangoli e cerchi si disegnano direttamente.
module Icons {

    // ----- Cuore (frequenza cardiaca) -----

    // Poligono derivato dal path SVG (viewBox 16x16, centrato in 8,8).
    // s mappa così che la mezza-altezza del cuore = size pixel.
    function buildHeart(cx, cy, size) {
        var s = size.toFloat() / 7.0;
        return [
            [cx,                         cy + (7.0 * s).toNumber()],  // punta bassa
            [cx + (7.0 * s).toNumber(),  cy + (0.5 * s).toNumber()],  // spalla destra
            [cx + (8.0 * s).toNumber(),  cy - (2.8 * s).toNumber()],  // estremo destra
            [cx + (7.5 * s).toNumber(),  cy - (5.0 * s).toNumber()],  // lobo dx alto
            [cx + (4.0 * s).toNumber(),  cy - (7.0 * s).toNumber()],  // cima lobo dx
            [cx + (1.5 * s).toNumber(),  cy - (6.5 * s).toNumber()],  // tacca dx
            [cx,                         cy - (4.5 * s).toNumber()],  // centro tacca
            [cx - (1.5 * s).toNumber(),  cy - (6.5 * s).toNumber()],  // tacca sx
            [cx - (4.0 * s).toNumber(),  cy - (7.0 * s).toNumber()],  // cima lobo sx
            [cx - (7.5 * s).toNumber(),  cy - (5.0 * s).toNumber()],  // lobo sx alto
            [cx - (8.0 * s).toNumber(),  cy - (2.8 * s).toNumber()],  // estremo sinistra
            [cx - (7.0 * s).toNumber(),  cy + (0.5 * s).toNumber()]   // spalla sinistra
        ];
    }

    function drawHeart(dc, pts) {
        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    // ----- Scarpa (passi) -----

    // Poligono derivato dalla SVG (viewBox 512x512).
    // ys = mezza-altezza, xs = mezza-larghezza (rapporto ~2.15:1).
    function buildShoe(cx, cy, size) {
        var ys = size.toFloat();
        var xs = ys * 2.15;
        return [
            [cx + (xs * 0.96).toNumber(), cy - (ys * 0.05).toNumber()],  // punta destra
            [cx + (xs * 0.12).toNumber(), cy - (ys * 1.00).toNumber()],  // lacci (top)
            [cx - (xs * 0.13).toNumber(), cy - (ys * 0.85).toNumber()],  // lingua
            [cx - (xs * 0.18).toNumber(), cy - (ys * 0.63).toNumber()],  // sotto lingua
            [cx - (xs * 0.55).toNumber(), cy - (ys * 0.40).toNumber()],  // caviglia
            [cx - (xs * 0.84).toNumber(), cy - (ys * 0.75).toNumber()],  // tallone alto
            [cx - (xs * 0.98).toNumber(), cy - (ys * 0.73).toNumber()],  // tallone sx
            [cx - (xs * 0.99).toNumber(), cy + (ys * 1.00).toNumber()],  // suola sx
            [cx + (xs * 0.97).toNumber(), cy + (ys * 1.00).toNumber()],  // suola dx
            [cx + (xs * 0.96).toNumber(), cy + (ys * 0.54).toNumber()]   // punta dx basso
        ];
    }

    function drawShoe(dc, pts) {
        dc.setColor(Gfx.COLOR_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    // ----- Montagna (altitudine) -----

    // Ritorna [corpo, cima innevata].
    function buildMountain(cx, cy, size) {
        var h = size;
        var w = size + 4;
        var baseY = cy + h / 2;
        var topY  = cy - h / 2;
        return [
            [[cx - w / 2, baseY], [cx, topY], [cx + w / 2, baseY]],
            [[cx - 2, topY + 4],  [cx, topY], [cx + 2, topY + 4]]
        ];
    }

    function drawMountain(dc, geom) {
        dc.setColor(Gfx.COLOR_DK_GREEN, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(geom[0]);
        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(geom[1]);
    }

    // ----- Termometro con sole (minima/massima) -----

    // Fedele alla SVG: stelo+bulbo a sinistra, sole con raggi a destra.
    // Ritorna [tx, topY, bulbY, bulbR, fillTop, sx, sy, sr, raggi], dove
    // raggi = [x1,y1,x2,y2, ...].
    function buildThermometer(cx, cy, size) {
        var s = size.toFloat();

        var tx    = cx - (s * 0.30).toNumber();
        var topY  = cy - (s * 0.50).toNumber();
        var bulbR = (s * 0.22).toNumber();
        if (bulbR < 2) { bulbR = 2; }
        var bulbY   = cy + (s * 0.28).toNumber();
        var fillTop = cy - (s * 0.08).toNumber();

        var sx = cx + (s * 0.12).toNumber();
        var sy = cy - (s * 0.15).toNumber();
        var sr = (s * 0.22).toNumber();
        if (sr < 2) { sr = 2; }

        // Raggi su / su-dx / dx / giù-dx come nella SVG
        var angles = [-90, -45, 0, 45];
        var rays = new [4 * angles.size()];
        var rIn  = (sr + 1).toFloat();
        var rOut = (sr + 3).toFloat();
        for (var i = 0; i < angles.size(); i++) {
            var a = angles[i] * Math.PI / 180.0;
            rays[4 * i]     = (sx + rIn  * Math.cos(a)).toNumber();
            rays[4 * i + 1] = (sy + rIn  * Math.sin(a)).toNumber();
            rays[4 * i + 2] = (sx + rOut * Math.cos(a)).toNumber();
            rays[4 * i + 3] = (sy + rOut * Math.sin(a)).toNumber();
        }
        return [tx, topY, bulbY, bulbR, fillTop, sx, sy, sr, rays];
    }

    function drawThermometer(dc, g) {
        var tx = g[0];
        var topY = g[1];
        var bulbY = g[2];
        var bulbR = g[3];
        var fillTop = g[4];

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(tx - 1, topY, 2, bulbY - topY, 1);
        dc.fillCircle(tx, bulbY, bulbR);

        dc.setColor(Gfx.COLOR_RED, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(tx, bulbY, bulbR - 1);
        dc.fillRectangle(tx, fillTop, 1, bulbY - fillTop);

        dc.setColor(Gfx.COLOR_YELLOW, Gfx.COLOR_TRANSPARENT);
        dc.fillCircle(g[5], g[6], g[7]);
        dc.setPenWidth(1);
        drawLines(dc, g[8]);
    }

    // ----- Sole sull'orizzonte (alba/tramonto) -----

    // Semisole sull'orizzonte con raggi e freccia.
    // up = true → alba (freccia verso l'alto), false → tramonto (freccia in basso).
    // Ritorna [cupola, raggi, orizzonte, freccia]; raggi e orizzonte sono
    // linee nel formato [x1,y1,x2,y2, ...].
    function buildSunHorizon(cx, cy, size, up) {
        var hw = size / 2;            // mezza larghezza dell'orizzonte
        var hy = cy + 2;              // linea dell'orizzonte
        var r  = (size / 4.0) + 1.0;  // raggio del semisole

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

        // Raggi rivolti verso l'alto
        var angles = [-55, 0, 55];
        var rays = new [4 * angles.size()];
        for (var j = 0; j < angles.size(); j++) {
            var b = (angles[j] - 90) * Math.PI / 180.0;
            rays[4 * j]     = (cx + (r + 1) * Math.cos(b)).toNumber();
            rays[4 * j + 1] = (hy + (r + 1) * Math.sin(b)).toNumber();
            rays[4 * j + 2] = (cx + (r + 3) * Math.cos(b)).toNumber();
            rays[4 * j + 3] = (hy + (r + 3) * Math.sin(b)).toNumber();
        }

        // Freccia di direzione sotto l'orizzonte
        var ay = hy + 2;
        var arrow = up
            ? [[cx, ay], [cx - 3, ay + 4], [cx + 3, ay + 4]]
            : [[cx, ay + 4], [cx - 3, ay], [cx + 3, ay]];

        return [dome, rays, [cx - hw, hy, cx + hw, hy], arrow];
    }

    function drawSunHorizon(dc, g, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.fillPolygon(g[0]);
        drawLines(dc, g[1]);
        drawLines(dc, g[2]);
        dc.fillPolygon(g[3]);
    }

    // ----- Scale (piani) -----

    // 3 gradini ascendenti.
    function drawStairs(dc, cx, cy, size, color) {
        dc.setColor(color, Gfx.COLOR_TRANSPARENT);
        var step = size / 3;
        var left = cx - size / 2;
        dc.fillRectangle(left,            cy + step, size,            step - 1);
        dc.fillRectangle(left + step,     cy,        size - step,     step - 1);
        dc.fillRectangle(left + 2 * step, cy - step, size - 2 * step, step - 1);
    }

    // ----- Batteria -----

    // Contorno bianco con livello di riempimento nel colore della carica.
    function drawBattery(dc, cx, cy, pct, color) {
        var bw = 18;
        var bh = 9;
        var tipW = 2;
        var tipH = 4;
        var bx = cx - (bw + tipW) / 2;
        var by = cy - bh / 2;

        dc.setColor(Gfx.COLOR_WHITE, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawRoundedRectangle(bx, by, bw, bh, 2);
        dc.fillRectangle(bx + bw, by + (bh - tipH) / 2, tipW, tipH);

        var fillW = (bw - 2) * pct / 100;
        if (fillW > 0) {
            dc.setColor(color, Gfx.COLOR_TRANSPARENT);
            dc.fillRectangle(bx + 1, by + 1, fillW, bh - 2);
        }
    }

    // ----- Fulmine (minuti di attività intensa) -----

    // Fulmine stilizzato; size = mezza-altezza in pixel.
    function buildBolt(cx, cy, size) {
        var s = size.toFloat() / 7.0;
        return [
            [cx + (2.0 * s).toNumber(), cy - (7.0 * s).toNumber()],  // punta alta
            [cx - (4.0 * s).toNumber(), cy + (1.0 * s).toNumber()],
            [cx,                        cy + (1.0 * s).toNumber()],
            [cx - (2.0 * s).toNumber(), cy + (7.0 * s).toNumber()],  // punta bassa
            [cx + (4.0 * s).toNumber(), cy - (1.0 * s).toNumber()],
            [cx,                        cy - (1.0 * s).toNumber()]
        ];
    }

    function drawBolt(dc, pts) {
        dc.setColor(Gfx.COLOR_ORANGE, Gfx.COLOR_TRANSPARENT);
        dc.fillPolygon(pts);
    }

    // ----- Telefono connesso -----

    function drawPhone(dc, cx, cy, w, h) {
        var x = cx - w / 2;
        var y = cy - h / 2;

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

    // ----- Helper -----

    // Disegna una lista di segmenti nel formato [x1,y1,x2,y2, ...].
    function drawLines(dc, lines) {
        for (var i = 0; i < lines.size(); i += 4) {
            dc.drawLine(lines[i], lines[i + 1], lines[i + 2], lines[i + 3]);
        }
    }
}
