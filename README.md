# Garmin Fenix 6 Pro Watchface

Watchface Connect IQ per **Garmin Fenix 6 Pro** che mostra:

- Orario corrente (24h o 12h secondo le impostazioni dell'orologio)
- Data (giorno settimana, giorno, mese)
- **Frequenza cardiaca** corrente (con icona cuore)
- **Icona meteo** + temperatura (da `Toybox.Weather`)
- **Altitudine** corrente (m o ft, da barometro/GPS)
- Prossimo evento solare: **alba** o **tramonto** (a seconda di quale viene
  prima rispetto all'ora attuale; dopo il tramonto mostra l'alba di domani)
- **Passi** effettuati + obiettivo giornaliero
- **Batteria** residua (icona + percentuale)
- **Piani saliti** (floors climbed) + obiettivo

## Layout (260x260, Fenix 6 Pro)

Layout radiale stile Fenix di default: orario e data al centro, sette
campi dati distribuiti sul perimetro a 45° l'uno dall'altro.

```
                    ❤ 72            <- 12: HR
              ┌──────────────┐
        ☀22° │                │ 🪜      <- 1:30 meteo / 3 piani
             │     12:34      │
             │    19/05/26    │ ALBA   <- 4:30 prossimo evento solare
        ▲451│                │ 06:12
              └──────────────┘
        👟7421       ▼ 451m            <- 7:30 passi / 6 altitudine
              [■■]45%                  <- 9: batteria
```

## Struttura progetto

```
manifest.xml                  -> manifest applicazione (target: fenix6pro)
monkey.jungle                 -> file di build
resources/
  drawables/                  -> icona launcher
  strings/strings.xml         -> stringhe localizzate
  properties.xml              -> properties (ultima posizione salvata)
source/
  FenixWatchfaceApp.mc        -> entry point AppBase
  FenixWatchfaceView.mc       -> rendering watchface
  SunCalc.mc                  -> calcolo alba/tramonto
  WeatherIcons.mc             -> icone meteo vettoriali
```

## Build

Requisiti:

- [Garmin Connect IQ SDK](https://developer.garmin.com/connect-iq/sdk/) (>= 4.x)
- SDK Manager con il device **fenix6pro** installato
- Una developer key (`developer_key.der`)

Build da CLI:

```bash
monkeyc \
  -d fenix6pro \
  -f monkey.jungle \
  -o FenixWatchface.prg \
  -y /path/to/developer_key.der
```

Esecuzione sul simulatore:

```bash
connectiq        # avvia il simulatore
monkeydo FenixWatchface.prg fenix6pro
```

In **VS Code** con l'estensione "Monkey C", basta aprire la cartella ed eseguire
*Monkey C: Build for Device* → *fenix6pro*.

## Note

- L'orario di alba/tramonto richiede una posizione GPS valida. Alla prima
  installazione potrebbe mostrare `--:--` finché l'orologio non ottiene un fix.
  La posizione viene salvata e riutilizzata.
- Il calcolo astronomico è basato sull'algoritmo NOAA (precisione ~1 minuto).
- I "piani" usano `ActivityMonitor.floorsClimbed`, supportato dal Fenix 6 Pro
  grazie all'altimetro barometrico.
- La frequenza cardiaca usa `Activity.getActivityInfo().currentHeartRate` con
  fallback a `ActivityMonitor.getHeartRateHistory` (ultimo campione).
- Il meteo arriva da `Toybox.Weather.getCurrentConditions()` (richiede che
  l'orologio sia sincronizzato con Garmin Connect, CIQ >= 3.2.0). La
  temperatura segue l'unità impostata sull'orologio (°C / °F).
