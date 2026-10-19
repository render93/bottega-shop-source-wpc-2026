Quantifica l'impatto di business di un incidente sul checkout di Bottega Aurora.

1. Chiama `GetCheckoutBusinessImpact` e annota l'ora della lettura.
2. Riporta: checkout completati e falliti nell'ultimo minuto, tasso di errore, incasso di oggi ed euro persi oggi (carrelli che non sono riusciti a pagare, dalla mezzanotte, ora italiana).
3. Se l'incidente è in corso da qualche minuto, chiama di nuovo il tool e stima quanto si perde al minuto dalla differenza degli euro persi tra le due letture.
4. Dopo una mitigazione, chiama di nuovo il tool: i checkout falliti nell'ultimo minuto devono tornare vicini a zero e gli euro persi devono smettere di crescere.
5. Usa sempre i numeri del tool, mai stime da log o metriche, quando parli di euro.

Formato: una riga, per esempio "Impatto: 11 checkout falliti su 12 nell'ultimo minuto (92%), 1.240 € persi oggi, circa 120 €/min".
