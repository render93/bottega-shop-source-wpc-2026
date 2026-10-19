# Architettura di Bottega Aurora

Negozio online di panettoni e dolci delle feste. Un'unica applicazione .NET 10 serve la vetrina, la sala di controllo e le API.

## Componenti

- **Web App** su App Service Linux, piano P0v3 con un'istanza. Due slot: `production` (traffico dei clienti) e `staging` (versione successiva, pronta per la promozione). Lo slot si distingue in telemetria con l'attributo `app.slot`.
- **Vetrina** (`/`) e **sala di controllo** (`/#sala`): pagine statiche servite dalla stessa Web App. La sala di controllo mostra ordini al minuto, incasso del giorno ed euro persi, letti da `GET /api/live` ogni 2 secondi.
- **API**: `GET /api/products`, `POST /api/checkout`, `GET /api/live`, `GET /api/orders/feed`, `GET /api/version`.
- **Pagamento**: autorizzazione con un round trip di circa 80 ms. Il tempo massimo è l'impostazione dello slot `PAYMENT_TIMEOUT_MS` (predefinito 3000 ms).
- **Azure SQL**, database `aurora`, tabella `dbo.Checkouts`: ogni checkout, completato o fallito, con importo e articoli. L'app accede con la managed identity `id-aurora-shop`, solo lettura e scrittura delle righe; le migrazioni stanno in `db/migrations`.
- **Telemetria**: OpenTelemetry verso Application Insights e Log Analytics. La versione dell'app è `service.version`, compilata nell'assembly.

## Rilascio

- Ogni modifica passa da una pull request su `main`. Dopo il merge sul codice dell'app (`src`, `tests`) il workflow "CI/CD" esegue i test, distribuisce nello slot `staging` e scambia gli slot.
- Il workflow "Deploy version" distribuisce un tag o un commit in un solo slot, senza scambio.
- Il workflow "Promote to production" esegue solo lo swap staging -> production. "Emergency rollback" scambia di nuovo production e staging: dopo una promozione lo slot staging contiene la versione precedente.

## Monitoraggio e reperibilità

- Alert `alert-checkout-5xx`: più di 3 errori 5xx al minuto sulla Web App (metrica `Http5xx`, che copre lo slot production), valutato ogni minuto.
- Il reperibile segue il canale Teams `bottega-aurora-oncall`.
- Traffico tipico: circa 12 ordini al minuto.
