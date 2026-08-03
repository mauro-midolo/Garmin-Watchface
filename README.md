# Garmin Fenix 6 Pro Watchface

Watchface Connect IQ per **Garmin Fenix 6 Pro** con un layout radiale che mostra a colpo d'occhio le informazioni più importanti della giornata.

---

## Cosa mostra

### Centro del quadrante

| Elemento | Descrizione |
|----------|-------------|
| Orario | Ora corrente in formato 24h o 12h (segue l'impostazione dell'orologio) |
| Secondi | Mostrati sopra l'orario, solo quando l'orologio è "sveglio" (high-power mode); nascosti in risparmio energetico per non mostrare un valore fermo |
| Data | Giorno della settimana abbreviato + data `GG/MM/AA` (es. `MER 25/06/26`), sotto un separatore blu |
| Fase lunare 🌙 | Glifo vettoriale della fase lunare corrente, disegnato sotto la data (calcolo astronomico, aggiornato una volta al giorno) |
| Telefono connesso 📱 | Icona dello smartphone sopra l'orario, mostrata **solo** quando il telefono è connesso |

### Campi radiali

I campi sono disposti in senso orario nelle posizioni a mezz'ora attorno al quadrante:

| Posizione | Informazione |
|-----------|-------------|
| 1:30 | Condizioni meteo attuali + temperatura ☀ |
| 2:30 | Temperatura min/max prevista per la giornata 🌡 (`min°/max°`) |
| 3:30 | Altitudine attuale ▲ (m o ft) |
| 4:30 | Passi effettuati oggi 👟 (in verde al raggiungimento dell'obiettivo) |
| 5:30 | Tramonto 🌇 |
| 6:30 | Alba 🌅 (la prossima disponibile) |
| 7:30 | Piani saliti oggi 🪜 (`saliti/obiettivo`, in verde al raggiungimento dell'obiettivo) |
| 8:30 | Autonomia residua della batteria in giorni |
| 9:30 | Batteria residua 🔋 (percentuale, colore verde/giallo/rosso) |
| 10:30 | Frequenza cardiaca ❤ |

### Anello delle fasi del giorno

Attorno al bordo è presente un **anello 24h delle fasi del giorno**: archi colorati mostrano la durata di notte (**blu**), crepuscolo civile (**rosso**) e luce piena (**giallo**), calcolati in base ad alba/tramonto. Le tacche orarie bianche segnano le ore; una **barretta bianca** evidenzia l'ora corrente.

---

## Compatibilità

- **Garmin Fenix 6 Pro** (display radiale 260×260)
- Richiede **Garmin Connect IQ 4.x** o superiore
- Sincronizzazione con **Garmin Connect** per il meteo

---

## Installazione

1. Apri l'app **Garmin Connect** sul tuo smartphone.
2. Cerca la watchface *Fenix Watchface* nel **Connect IQ Store**.
3. Tocca **Installa**: la watchface verrà trasferita automaticamente all'orologio.
4. Sul Garmin, tieni premuto il tasto **UP** → *Imposta orologio* → scegli la watchface.

---

## Note sull'utilizzo

- **Alba/tramonto**: la posizione usata per il calcolo è ricavata dai dati meteo (località di osservazione), quindi richiede la sincronizzazione con Garmin Connect. Alla prima installazione potrebbe apparire `--:--` finché i dati meteo non sono disponibili; la posizione viene poi salvata e riutilizzata automaticamente. Il campo "alba" mostra la prossima alba (di domani se quella di oggi è già passata).
- **Fase lunare**: calcolata astronomicamente dalla sola data, senza sensori, GPS o rete; il glifo viene aggiornato una volta al giorno.
- **Meteo**: i dati meteo richiedono che l'orologio sia sincronizzato con Garmin Connect tramite Bluetooth. Temperatura e unità di misura seguono le impostazioni dell'orologio (°C / °F).
- **Frequenza cardiaca**: visualizza la frequenza cardiaca in tempo reale durante un'attività; a riposo mostra l'ultimo campione disponibile.
- **Piani saliti**: rilevati tramite l'altimetro barometrico del Fenix 6 Pro; il contatore si azzera ogni mezzanotte.
- **Altitudine**: ricavata dall'altimetro barometrico; mostrata in metri o piedi secondo le impostazioni dell'orologio.
- **Batteria**: oltre alla percentuale residua, viene mostrata anche la stima dell'autonomia rimanente in giorni.
- **Secondi**: mostrati solo quando l'orologio è attivo; in modalità risparmio energetico vengono nascosti per non visualizzare un valore non aggiornato.
- **Consumo**: il disegno è ottimizzato per il budget energetico di una watchface. Le letture di sistema (impostazioni, meteo, attività, batteria, orario) vengono fatte **una sola volta per frame**; posizione GPS/meteo, alba/tramonto, fase lunare e stringa della data sono ricalcolati **una volta al giorno**; le coordinate di tacche orarie e campi radiali sono precalcolate all'avvio, così in `onUpdate` non resta alcuna trigonometria su angoli costanti.
