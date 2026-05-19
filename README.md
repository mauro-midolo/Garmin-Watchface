# Garmin Fenix 6 Pro Watchface

Watchface Connect IQ per **Garmin Fenix 6 Pro** che mostra:

- Orario corrente (24h o 12h secondo le impostazioni dell'orologio)
- Data (giorno settimana, giorno, mese)
- Ora di **alba** e **tramonto** (calcolate dalla posizione GPS dell'orologio)
- **Passi** effettuati + obiettivo giornaliero
- **Batteria** residua (icona + percentuale)
- **Piani saliti** (floors climbed) + obiettivo

## Layout (260x260, Fenix 6 Pro)

```
                +----------------------+
                |       12:34          |   <- orario grande
                |   LUN 19 MAG         |   <- data
                |  ALBA       TRAM     |
                |  06:12      20:45    |   <- alba / tramonto
                |       PASSI          |
                |     7421 / 10000     |
                |  [■■■  ] 65%  PIANI  |
                |               12/10  |
                +----------------------+
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
