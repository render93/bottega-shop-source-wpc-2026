# Runbook: rollback di una release con lo swap degli slot

Negozio Bottega Aurora, Web App con slot `staging` e `production`. Dopo una promozione lo slot staging contiene la versione precedente.

## Quando usarlo

Errori o regressioni iniziati subito dopo uno swap di promozione, con prove che li legano alla nuova versione.

## Passi

1. Confermare la correlazione: inizio degli errori rispetto all'ora dello swap (log attività), errori per versione (`service.version` in Application Insights).
2. Verificare le migrazioni: confrontare `db/migrations` tra la versione in produzione e quella in staging. Nessuna migrazione nuova: lo swap inverso è sicuro. Migrazioni nuove: valutare la compatibilità prima di procedere (vedi PM-2025-11).
3. Eseguire lo swap staging -> production.
4. Verificare entro 5 minuti: errori 5xx a zero sul checkout, ordini al minuto tornati ai valori di prima.
5. Comunicare l'esito al canale del reperibile e aprire una issue con la causa.
