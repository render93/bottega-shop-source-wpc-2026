# PM-2025-11: errori al checkout la notte del Black Friday 2025

Postmortem senza colpe. Stato: chiuso. Redatto dal team piattaforma il 2 dicembre 2025.

## Sintesi

Venerdì 28 novembre 2025, dalle 02:14 alle 02:51, circa il 40% dei checkout è fallito con errore 500. Ordini persi stimati: 1.180 carrelli, circa 38.000 euro. La causa era la release 2.1.0 delle carte regalo, promossa in produzione con lo swap notturno degli slot.

## Cronologia (ora italiana)

- 02:10 swap della release 2.1.0 dallo slot staging a production.
- 02:14 primi errori sul checkout; alert alle 02:18.
- 02:22 il reperibile identifica la release come causa e avvia il rollback con uno swap inverso.
- 02:24 il rollback non risolve: gli errori cambiano ma restano. La 2.1.0 aveva applicato una migrazione del database (nuova colonna obbligatoria) che la 2.0.4 non sapeva gestire.
- 02:40 si decide di tornare alla 2.1.0 e di correggere in avanti con una 2.1.1.
- 02:51 2.1.1 in produzione, checkout regolare.

## Cause

- Il percorso di codice nuovo (pagamento con carta regalo) non era coperto dai test automatici.
- La release conteneva una migrazione non retrocompatibile: il rollback con lo swap non era sicuro e nessuno lo sapeva.

## Lezioni

1. **Prima di un rollback con lo swap, verificare se la release contiene migrazioni del database** (cartella `db/migrations`). Se non ce ne sono, lo swap inverso è sicuro e veloce; se ce ne sono, valutare se la versione precedente le regge.
2. Confrontare gli errori per versione (`service.version` in Application Insights) prima di attribuire la colpa a una release.
3. Dopo la mitigazione, aprire subito una issue con la causa e un test che riproduca il difetto.

## Azioni

- Le migrazioni devono essere retrocompatibili per almeno una versione (fatto).
- Runbook del rollback con swap degli slot (fatto: `runbook-slot-rollback.md`).
