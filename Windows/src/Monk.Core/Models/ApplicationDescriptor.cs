namespace Monk.Core.Models;

public sealed record ApplicationDescriptor(
    string Id,
    string DisplayName,
    string ExecutablePath,
    string? PackageFamilyName = null,
    string? AppUserModelId = null)
{
    public bool IsPackaged => !string.IsNullOrWhiteSpace(PackageFamilyName);

    public static ApplicationDescriptor FromExecutable(string displayName, string executablePath)
    {
        var fullPath = Path.GetFullPath(executablePath);
        return new ApplicationDescriptor(fullPath.ToUpperInvariant(), displayName, fullPath);
    }

    public static ApplicationDescriptor FromPackagedApplication(
        string displayName,
        string appUserModelId)
    {
        var separator = appUserModelId.IndexOf('!');
        if (separator <= 0 || separator == appUserModelId.Length - 1)
        {
            throw new ArgumentException("A packaged application ID is required.", nameof(appUserModelId));
        }

        var packageFamilyName = appUserModelId[..separator];
        return new ApplicationDescriptor(
            "package:" + appUserModelId.ToUpperInvariant(),
            displayName.Trim(),
            "",
            packageFamilyName,
            appUserModelId);
    }
}
