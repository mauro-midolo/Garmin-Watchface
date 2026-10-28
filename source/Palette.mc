using Toybox.Graphics as Gfx;

// Colori condivisi della watchface.
//
// Il Fenix 6 Pro ha un display MIP a 64 colori: ogni canale RGB può valere
// solo 0x00, 0x55, 0xAA o 0xFF. Un colore fuori palette viene arrotondato dal
// device al più vicino (es. 0x0066CC diventa 0x0055AA), quindi qui si usano
// solo valori già presenti nella palette: ciò che si vede nel codice è ciò che
// si vede sull'orologio.
module Palette {

    // Blu d'accento: separatore orario/data e icona dei piani.
    const ACCENT       = 0x0055FF;
    // Azzurro chiaro: data.
    const ACCENT_LIGHT = 0x55AAFF;

    // Anello 24h delle fasi del giorno: notte blu, crepuscolo rosso, giorno giallo.
    const RING_NIGHT    = Gfx.COLOR_BLUE;
    const RING_TWILIGHT = Gfx.COLOR_RED;
    const RING_DAY      = Gfx.COLOR_YELLOW;

    // Valore di un campo con obiettivo raggiunto (passi, piani).
    const GOAL = Gfx.COLOR_GREEN;
}
