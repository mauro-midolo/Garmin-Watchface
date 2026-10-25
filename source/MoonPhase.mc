using Toybox.Graphics as Gfx;
using Toybox.Math;

// Fase lunare: calcolo astronomico e glifo vettoriale.
//
// Puro calcolo a partire dalla data corrente: NESSUN sensore, GPS o chiamata
// di rete. Il calcolo (compreso il poligono del glifo) avviene UNA SOLA VOLTA
// AL GIORNO e resta in cache; a ogni frame si disegna soltanto.
class MoonPhase {

    // Mese sinodico medio (giorni tra due noviluni consecutivi): periodo del
    // ciclo delle fasi lunari usato per il calcolo astronomico.
    const SYNODIC_MONTH = 29.530588853;

    // Novilunio di riferimento: 6 gennaio 2000, 18:14 UTC, in secondi dall'epoca
    // Unix. Valore costante e già in UTC: Gregorian.moment() NON è utilizzabile
    // perché interpreta i campi come ora locale (errore fino a ±14 ore).
    const REF_NEW_MOON_EPOCH = 947182440;

    // Centro e raggio del glifo: unica fonte per calcolo e disegno.
    hidden var mx;
    hidden var my;
    hidden var radius;

    hidden var lastDay = -1;
    hidden var lastSouthern = false;
    // Poligono della regione illuminata, precalcolato (null = non ancora pronto).
    hidden var poly = null;

    function initialize(x, y, r) {
        mx = x;
        my = y;
        radius = r;
    }

    // Ricalcola la fase solo al cambio giorno o di emisfero.
    //
    // FORMULA: si misura l'"età" della luna come tempo trascorso da un
    // novilunio di riferimento noto, riportato nel mese sinodico medio
    // (~29.53 giorni). La frazione del ciclo (0..1) dà fase e illuminazione.
    //
    // southern: true nell'emisfero sud, dove la luna crescente è illuminata a
    // sinistra invece che a destra.
    function update(dayKey, now, southern) {
        if (dayKey == lastDay && southern == lastSouthern) { return; }

        // Giorni trascorsi dal novilunio di riferimento (entrambi in UTC).
        var elapsedDays = (now.value() - REF_NEW_MOON_EPOCH) / 86400.0;

        // Frazione del ciclo sinodico corrente: phase in [0, 1).
        //   0   = novilunio, 0.5 = plenilunio.
        var phase = elapsedDays / SYNODIC_MONTH;
        phase = phase - Math.floor(phase);
        if (phase < 0.0) { phase += 1.0; }

        // Frazione illuminata del disco: 0 (novilunio) → 1 (plenilunio) → 0.
        var fraction = (1.0 - Math.cos(2.0 * Math.PI * phase)) / 2.0;
        // Nell'emisfero nord la luna crescente (prima metà del ciclo) ha il
        // limbo illuminato a destra; nell'emisfero sud è il contrario.
        var litRight = (phase < 0.5) != southern;

        poly = buildPolygon(fraction, litRight);
        lastDay = dayKey;
        lastSouthern = southern;
    }

    // Costruisce il poligono della regione illuminata: si scende lungo il limbo
    // circolare e si risale lungo il terminatore (semi-ellisse di semilarghezza
    // k volte quella del limbo a ciascuna quota).
    hidden function buildPolygon(fraction, litRight) {
        var R = radius;
        // k: posizione orizzontale del terminatore relativa al limbo (-1..1).
        //   f=0  → k=1  (terminatore sul limbo: nessuna porzione illuminata)
        //   f=.5 → k=0  (terminatore verticale: mezzo disco illuminato)
        //   f=1  → k=-1 (terminatore sul limbo opposto: disco pieno)
        var k = 1.0 - 2.0 * fraction;
        var sign = litRight ? 1.0 : -1.0;

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
        return pts;
    }

    // Disco in ombra + contorno (sempre visibile, anche al novilunio) +
    // poligono illuminato già pronto in cache.
    function draw(dc) {
        if (poly == null) { return; }

        dc.setColor(Gfx.COLOR_DK_GRAY, Gfx.COLOR_BLACK);
        dc.fillCircle(mx, my, radius);
        dc.setColor(Gfx.COLOR_LT_GRAY, Gfx.COLOR_TRANSPARENT);
        dc.setPenWidth(1);
        dc.drawCircle(mx, my, radius);
        dc.fillPolygon(poly);
    }
}
