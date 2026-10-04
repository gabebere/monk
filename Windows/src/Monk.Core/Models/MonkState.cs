namespace Monk.Core.Models;

public sealed record MonkSettings(
    bool DefaultBlockingEnabled,
    IReadOnlyList<ApplicationDescriptor> AlwaysAllowedApplications)
{
    public static MonkSettings Default { get; } = new(false, []);
}

public sealed record MonkState(
    FocusPolicy? ActivePolicy,
    MonkSettings Settings,
    long Revision)
{
    public static MonkState Empty { get; } = new(null, MonkSettings.Default, 0);
}

public sealed record BrowserPolicy(
    bool Enforcing,
    IReadOnlyList<string> AllowedDomains,
    long Revision);
