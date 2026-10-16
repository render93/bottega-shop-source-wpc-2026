using Azure.Monitor.OpenTelemetry.AspNetCore;
using OpenTelemetry.Instrumentation.AspNetCore;
using OpenTelemetry.Resources;

namespace BottegaAurora.Shop.Telemetry;

public static class TelemetrySetup
{
    public const string ServiceName = "bottega-aurora";

    public static void AddShopTelemetry(this WebApplicationBuilder builder)
    {
        // Without a connection string (local runs, tests) there is nothing to export to.
        if (string.IsNullOrEmpty(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"])) return;

        builder.Services.AddOpenTelemetry()
            .ConfigureResource(r => r.AddService(ServiceName, serviceVersion: AppVersion.Current))
            .UseAzureMonitor();

        builder.Services.Configure<AspNetCoreTraceInstrumentationOptions>(o =>
            o.EnrichWithHttpRequest = (activity, request) => activity.SetTag("app.slot", Slot.FromHost(request.Host.Host)));
    }
}
