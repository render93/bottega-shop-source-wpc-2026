namespace BottegaAurora.Shop.Payments;

// Authorizes the card payment with the payment provider; PAYMENT_TIMEOUT_MS bounds the wait.
public sealed class PaymentGateway(IConfiguration configuration)
{
    public const string TimeoutSetting = "PAYMENT_TIMEOUT_MS";
    public const int DefaultTimeoutMs = 3000;

    private static readonly TimeSpan RoundTrip = TimeSpan.FromMilliseconds(80);

    public TimeSpan Timeout { get; } =
        TimeSpan.FromMilliseconds(configuration.GetValue(TimeoutSetting, DefaultTimeoutMs));

    public async Task<string> AuthorizeAsync(decimal amount, CancellationToken cancellationToken)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        cts.CancelAfter(Timeout);
        try
        {
            await Task.Delay(RoundTrip, cts.Token);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            throw new TimeoutException($"Payment authorization timed out after {Timeout.TotalMilliseconds} ms");
        }

        return $"AUTH-{Guid.NewGuid():N}"[..17].ToUpperInvariant();
    }
}
