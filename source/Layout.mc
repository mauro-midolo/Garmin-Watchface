// Costanti di layout per il display 260x260 del Fenix 6 Pro.
//
// Tutte le posizioni sono espresse come offset dal centro dello schermo, così
// la disposizione si legge e si modifica in un punto solo. La geometria
// derivata (posizioni dei campi, tacche, icone) è calcolata una volta sola in
// FenixWatchfaceView.onLayout.
module Layout {

    // ----- Colonna centrale (offset verticali dal centro) -----
    const PHONE_DY         = -90;  // icona telefono connesso
    const PHONE_W          = 14;
    const PHONE_H          = 24;
    const SECONDS_DY       = -58;  // secondi, sopra l'orario
    const TIME_DY          = -12;  // orario
    const SEPARATOR_DY     = 20;   // linea tra orario e data
    const SEPARATOR_HALF_W = 40;
    const DATE_DY          = 35;   // data
    const MOON_DY          = 62;   // centro del glifo lunare
    const MOON_R           = 13;   // raggio del glifo lunare

    // ----- Anello esterno e tacche (rientri dal bordo) -----
    const RING_INSET          = 3;   // raggio dell'anello = centro - 3
    const RING_PEN            = 5;
    const TICK_OUTER_INSET    = 6;
    const TICK_INNER_INSET    = 11;  // tacche normali
    const TICK_CARDINAL_INSET = 17;  // tacche a 0/6/12/18

    // ----- Campi radiali -----
    // 10 slot da 30° a partire da 45° (45°, 75°, ..., 315°). Sull'anello 24h
    // una tacca vale 15°, quindi ogni slot è allineato alla tacca delle ore
    // 3, 5, 7, ..., 21: i campi stanno all'interno del cerchio delle tacche,
    // sul loro prolungamento.
    const FIELD_COUNT      = 10;
    const FIELD_FIRST_DEG  = 45.0;
    const FIELD_STEP_DEG   = 30.0;
    // Raggio massimo di uno slot, in frazione del raggio dello schermo. Gli
    // slot più vicini al bordo vengono avvicinati al centro quanto basta per
    // tenere il testo dentro al cerchio delle tacche (vedi buildFieldPositions).
    const FIELD_RADIUS_MAX = 0.75;
    // Distanza minima, in pixel, tra il testo dei campi e le tacche.
    const FIELD_TEXT_MARGIN = 2;
    // Icona sopra e valore sotto il centro dello slot: uguali per tutti i campi,
    // così i valori stanno tutti alla stessa distanza dal centro dello slot.
    const ICON_DY  = -8;
    const VALUE_DY = 9;
    // Testo di riferimento per lo spazio riservato al valore di uno slot.
    const FIELD_REF_TEXT = "00000";
    // Spostamento massimo verso il centro di un valore più largo dello spazio
    // disponibile verso il bordo, prima di ripiegare sulla forma abbreviata.
    const FIELD_SHIFT_MAX = 8;
}
