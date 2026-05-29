# CLAUDE.md

Questo file fornisce indicazioni a Claude Code (claude.ai/code) quando lavora su questo repository.

## Panoramica del progetto

Watchface **Connect IQ** per **Garmin Fenix 6 Pro**, scritta in **Monkey C**.
Display radiale 260x260

## Workflow Git — REGOLA FONDAMENTALE

**Non committare MAI direttamente su `main`.** Ogni modifica al codice deve passare
da una pull request.

Per ogni intervento che modifica file del repository, Claude deve:

1. **Auto-assegnazione e label dell'issue** — prima di iniziare qualsiasi lavoro
   su un'issue, eseguire automaticamente:
   ```
   gh issue edit <numero> --add-assignee "@me"
   gh issue edit <numero> --add-label "<etichetta-appropriata>"
   ```
   Scegliere l'etichetta in base al tipo di modifica:
   - `enhancement` — nuova funzionalità o miglioramento
   - `bug` — correzione di un errore
   - `refactor` — riorganizzazione del codice senza cambio di comportamento
   - `documentation` — modifiche solo alla documentazione
   - `automation` — configurazione di workflow o automazione

2. Creare un nuovo branch dedicato a partire da `main` aggiornato:
   ```
   git checkout main
   git pull origin main
   git checkout -b claude/<descrizione-breve>
   ```
   I branch creati da Claude usano sempre il prefisso `claude/` (la CI è già
   configurata per girare su `claude/**`).

3. Fare commit atomici e con messaggi chiari in italiano sul branch.

4. Fare push del branch e **aprire sempre una pull request verso `main`** usando
   `gh pr create` (NON limitarsi a fornire un link):
   ```
   git push -u origin claude/<descrizione-breve>
   gh pr create \
     --base main \
     --title "<titolo>" \
     --body "$(cat <<'EOF'
   ## Sommario
   <descrizione delle modifiche>

   Risolve #<numero-issue>

   Generated with [Claude Code](https://claude.ai/code)
   EOF
   )"
   ```

5. Nella descrizione della PR riassumere cosa è cambiato e perché. Lasciare che
   sia l'utente a fare il merge: **Claude non fa merge della PR**.

Anche per modifiche minime (fix, refactor, una singola riga) va comunque aperta
una PR — niente commit diretti su `main`.

## Build

Requisiti:
- Garmin Connect IQ SDK >= 4.x
- Device **fenix6pro** installato tramite SDK Manager
- Developer key (`developer_key.der`)

Build da CLI:
```
monkeyc \
  -d fenix6pro \
  -f monkey.jungle \
  -o FenixWatchface.prg \
  -y /path/to/developer_key.der
```

Esecuzione sul simulatore:
```
connectiq                                 # avvia il simulatore
monkeydo FenixWatchface.prg fenix6pro
```

## Convenzioni di codice

- Linguaggio: **Monkey C**. File sorgente in `source/`, un file per
  classe/responsabilità principale.
- Le stringhe visibili all'utente vanno in `resources/strings/strings.xml`, non
  hardcoded nel codice.
- Layout pensato per il display **260x260** del Fenix 6 Pro: mantenere le
  coordinate coerenti con la disposizione radiale a 45°.
- Rispettare i vincoli energetici di una watchface (codice in `onUpdate`
  efficiente, niente operazioni costose ad ogni frame).

## Note di dominio importanti

- **Alba/tramonto** (`SunCalc.mc`) richiedono una posizione GPS valida; alla prima
  installazione può mostrare `--:--` finché non c'è un fix. La posizione viene
  salvata in `properties.xml` e riutilizzata.
- **Frequenza cardiaca**: `Activity.getActivityInfo().currentHeartRate` con
  fallback a `ActivityMonitor.getHeartRateHistory` (ultimo campione).
- **Meteo**: `Toybox.Weather.getCurrentConditions()` (richiede sync con Garmin
  Connect, CIQ >= 3.2.0). L'unità di temperatura segue l'impostazione
  dell'orologio (°C / °F).
- **Piani saliti**: `ActivityMonitor.floorsClimbed` (altimetro barometrico del
  Fenix 6 Pro).
