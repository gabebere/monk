using System.Diagnostics;
using System.IO;
using System.Text.Json;
using Microsoft.Win32;
using Monk.Core.Models;

namespace Monk.App.Services;

public sealed class ApplicationCatalogService
{
    public IReadOnlyList<ApplicationDescriptor> Discover()
    {
        var applications = new Dictionary<string, ApplicationDescriptor>(StringComparer.OrdinalIgnoreCase);
        ReadRegistryHive(Registry.CurrentUser, @"Software\Microsoft\Windows\CurrentVersion\Uninstall", applications);
        ReadRegistryHive(Registry.LocalMachine, @"Software\Microsoft\Windows\CurrentVersion\Uninstall", applications);
        ReadRegistryHive(Registry.LocalMachine, @"Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall", applications);
        ReadPackagedApplications(applications);
        ReadRunningApplications(applications);

        return applications.Values
            .OrderBy(application => application.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();
    }

    private static void ReadPackagedApplications(
        IDictionary<string, ApplicationDescriptor> applications)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            Arguments = "-NoLogo -NoProfile -NonInteractive -Command \"" +
                "Get-StartApps | Where-Object { $_.AppID -like '*!*' } | " +
                "Select-Object Name,AppID | ConvertTo-Json -Compress\"",
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };

        try
        {
            using var process = Process.Start(startInfo);
            if (process is null)
            {
                return;
            }

            var json = process.StandardOutput.ReadToEnd();
            if (!process.WaitForExit(10_000) || process.ExitCode != 0 || string.IsNullOrWhiteSpace(json))
            {
                if (!process.HasExited)
                {
                    process.Kill(true);
                }
                return;
            }

            using var document = JsonDocument.Parse(json);
            var entries = document.RootElement.ValueKind == JsonValueKind.Array
                ? document.RootElement.EnumerateArray().ToArray()
                : [document.RootElement];

            foreach (var entry in entries)
            {
                if (!entry.TryGetProperty("Name", out var nameProperty) ||
                    !entry.TryGetProperty("AppID", out var idProperty) ||
                    nameProperty.GetString() is not { } displayName ||
                    idProperty.GetString() is not { } appUserModelId ||
                    !IsUsefulPackagedApplication(displayName, appUserModelId))
                {
                    continue;
                }

                var descriptor = ApplicationDescriptor.FromPackagedApplication(
                    displayName,
                    appUserModelId);
                applications[descriptor.Id] = descriptor;
            }
        }
        catch (Exception exception) when (exception is
            System.ComponentModel.Win32Exception or
            InvalidOperationException or
            IOException or
            JsonException or
            ArgumentException)
        {
            // Packaged-app discovery is additive; traditional apps remain searchable.
        }
    }

    private static void ReadRegistryHive(
        RegistryKey hive,
        string path,
        IDictionary<string, ApplicationDescriptor> applications)
    {
        using var root = hive.OpenSubKey(path);
        if (root is null)
        {
            return;
        }

        foreach (var subkeyName in root.GetSubKeyNames())
        {
            using var key = root.OpenSubKey(subkeyName);
            var displayName = key?.GetValue("DisplayName") as string;
            var displayIcon = key?.GetValue("DisplayIcon") as string;
            var executable = CleanIconPath(displayIcon);
            if (string.IsNullOrWhiteSpace(displayName) ||
                executable is null ||
                !File.Exists(executable) ||
                !executable.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
                Convert.ToInt32(key?.GetValue("SystemComponent") ?? 0) == 1 ||
                key?.GetValue("ReleaseType") is not null ||
                key?.GetValue("ParentKeyName") is not null ||
                !IsUsefulApplication(displayName, executable))
            {
                continue;
            }

            Add(applications, displayName, executable);
        }
    }

    private static void ReadRunningApplications(IDictionary<string, ApplicationDescriptor> applications)
    {
        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    if (process.MainWindowHandle == IntPtr.Zero || process.MainModule?.FileName is not { } path)
                    {
                        continue;
                    }

                    var name = process.MainWindowTitle;
                    if (string.IsNullOrWhiteSpace(name))
                    {
                        name = Path.GetFileNameWithoutExtension(path);
                    }
                    if (IsUsefulApplication(name, path))
                    {
                        Add(applications, name, path);
                    }
                }
                catch (Exception exception) when (exception is System.ComponentModel.Win32Exception or InvalidOperationException)
                {
                    // Protected and short-lived processes are not user-selectable applications.
                }
            }
        }
    }

    private static string? CleanIconPath(string? rawValue)
    {
        if (string.IsNullOrWhiteSpace(rawValue))
        {
            return null;
        }

        var value = rawValue.Trim().Trim('"');
        var comma = value.LastIndexOf(',');
        if (comma > 2 && int.TryParse(value[(comma + 1)..], out _))
        {
            value = value[..comma];
        }
        return Environment.ExpandEnvironmentVariables(value.Trim('"'));
    }

    private static void Add(
        IDictionary<string, ApplicationDescriptor> applications,
        string displayName,
        string executablePath)
    {
        try
        {
            var descriptor = ApplicationDescriptor.FromExecutable(displayName, executablePath);
            applications[descriptor.Id] = descriptor;
        }
        catch (Exception exception) when (exception is ArgumentException or NotSupportedException)
        {
            // Ignore malformed third-party uninstall records.
        }
    }

    private static bool IsUsefulApplication(string displayName, string executablePath)
    {
        if (displayName.Equals("Monk", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var ignoredNameFragments = new[]
        {
            "redistributable", "runtime", "software development kit", "update for",
            "driver", "debugger", "tools for applications", "parallels tools"
        };
        if (ignoredNameFragments.Any(fragment =>
            displayName.Contains(fragment, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        var executableName = Path.GetFileNameWithoutExtension(executablePath);
        return !executableName.StartsWith("unins", StringComparison.OrdinalIgnoreCase) &&
            !executableName.Contains("updater", StringComparison.OrdinalIgnoreCase) &&
            !executableName.Equals("setup", StringComparison.OrdinalIgnoreCase) &&
            !executableName.Equals("installer", StringComparison.OrdinalIgnoreCase) &&
            !executableName.Equals("prl_cc", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsUsefulPackagedApplication(string displayName, string appUserModelId)
    {
        if (string.IsNullOrWhiteSpace(displayName) ||
            displayName.StartsWith("@{", StringComparison.Ordinal) ||
            displayName.StartsWith("ms-resource:", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        var ignoredIds = new[]
        {
            "Microsoft.Windows.ShellExperienceHost",
            "Microsoft.Windows.StartMenuExperienceHost",
            "MicrosoftWindows.Client.CBS",
            "Microsoft.AAD.BrokerPlugin",
            "Microsoft.AccountsControl",
            "Microsoft.LockApp",
            "Microsoft.Windows.Search"
        };
        return !ignoredIds.Any(id =>
            appUserModelId.StartsWith(id, StringComparison.OrdinalIgnoreCase));
    }
}
