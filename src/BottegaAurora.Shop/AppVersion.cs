using System.Reflection;

namespace BottegaAurora.Shop;

public static class AppVersion
{
    // InformationalVersion is "2.3.1+<commit sha>": keep the semantic version only.
    public static string Current { get; } =
        typeof(AppVersion).Assembly
            .GetCustomAttribute<AssemblyInformationalVersionAttribute>()!
            .InformationalVersion.Split('+')[0];
}
