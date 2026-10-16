namespace BottegaAurora.Shop.Telemetry;

public static class Slot
{
    // App Service slots answer on "<site>-<slot>.azurewebsites.net" (or "<site>-<slot>-<hash>.<region>.azurewebsites.net"
    // with unique default hostnames); the host of each request tells the truth even right after a swap,
    // unlike settings read at startup.
    public static string FromHost(string host)
    {
        if (host is "localhost" or "127.0.0.1" or "[::1]") return "local";
        var firstLabel = host.Split('.')[0];
        return firstLabel.Split('-').Contains("staging", StringComparer.OrdinalIgnoreCase) ? "staging" : "production";
    }
}
