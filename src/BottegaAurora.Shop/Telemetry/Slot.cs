namespace BottegaAurora.Shop.Telemetry;

public static class Slot
{
    // App Service slots answer on "<site>-<slot>.azurewebsites.net"; the host of each request
    // tells the truth even right after a swap, unlike settings read at startup.
    public static string FromHost(string host)
    {
        if (host is "localhost" or "127.0.0.1" or "[::1]") return "local";
        var firstLabel = host.Split('.')[0];
        var dash = firstLabel.LastIndexOf('-');
        return dash > 0 && firstLabel[(dash + 1)..] == "staging" ? "staging" : "production";
    }
}
