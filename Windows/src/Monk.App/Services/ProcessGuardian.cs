using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Monk.Core.Models;

namespace Monk.App.Services;

public sealed class ProcessGuardian : IDisposable
{
    private static readonly HashSet<string> PermanentlyAllowedProcessNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "explorer", "LockApp", "Monk", "SearchHost",
        "SecurityHealthSystray", "ShellExperienceHost", "StartMenuExperienceHost",
        "SystemSettings", "TextInputHost", "UserOOBEBroker", "WinLogon"
    };

    private static readonly HashSet<string> SupportedBrowserNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "brave", "chrome", "chromium", "msedge", "opera", "vivaldi"
    };

    private readonly System.Threading.Timer timer;
    private readonly Dictionary<int, DateTimeOffset> gracefulCloseDeadlines = [];
    private readonly object gate = new();
    private EnforcementPolicy? policy;
    private long generation;
    private bool scanRunning;

    public ProcessGuardian()
    {
        timer = new System.Threading.Timer(_ => Scan(), null, TimeSpan.Zero, TimeSpan.FromMilliseconds(350));
    }

    public event EventHandler<string>? BlockedApplication;

    public void Apply(
        bool enforcing,
        IEnumerable<ApplicationDescriptor> allowedApplications,
        bool allowSupportedBrowsers)
    {
        var allowedPaths = allowedApplications
            .Where(application => !string.IsNullOrWhiteSpace(application.ExecutablePath))
            .Select(application => Path.GetFullPath(application.ExecutablePath))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var allowedPackageFamilies = allowedApplications
            .Select(application => application.PackageFamilyName)
            .Where(packageFamily => !string.IsNullOrWhiteSpace(packageFamily))
            .Select(packageFamily => packageFamily!)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        lock (gate)
        {
            var next = enforcing
                ? new EnforcementPolicy(allowedPaths, allowedPackageFamilies, allowSupportedBrowsers)
                : null;
            if (Equals(policy, next))
            {
                return;
            }

            policy = next;
            generation++;
            gracefulCloseDeadlines.Clear();
        }
    }

    private void Scan()
    {
        lock (gate)
        {
            if (scanRunning)
            {
                return;
            }
            scanRunning = true;
        }

        try
        {
            ScanCore();
        }
        finally
        {
            lock (gate)
            {
                scanRunning = false;
            }
        }
    }

    private void ScanCore()
    {
        EnforcementPolicy? currentPolicy;
        long currentGeneration;
        lock (gate)
        {
            currentPolicy = policy;
            currentGeneration = generation;
        }
        if (currentPolicy is null)
        {
            return;
        }

        foreach (var process in Process.GetProcesses())
        {
            using (process)
            {
                try
                {
                    if (ShouldAllow(process, currentPolicy))
                    {
                        continue;
                    }

                    var displayName = string.IsNullOrWhiteSpace(process.MainWindowTitle)
                        ? process.ProcessName
                        : process.MainWindowTitle;

                    var now = DateTimeOffset.Now;
                    bool shouldKill;
                    lock (gate)
                    {
                        if (generation != currentGeneration || policy is null)
                        {
                            return;
                        }

                        if (!gracefulCloseDeadlines.TryGetValue(process.Id, out var deadline))
                        {
                            gracefulCloseDeadlines[process.Id] = now.AddSeconds(2);
                            shouldKill = !process.CloseMainWindow();
                        }
                        else
                        {
                            shouldKill = now >= deadline;
                        }
                    }

                    if (shouldKill)
                    {
                        process.Kill(true);
                    }
                    BlockedApplication?.Invoke(this, displayName);
                }
                catch (Exception exception) when (exception is
                    System.ComponentModel.Win32Exception or
                    InvalidOperationException or
                    NotSupportedException)
                {
                    // The process exited, is protected, or cannot be inspected by this user.
                }
            }
        }
    }

    private static bool ShouldAllow(Process process, EnforcementPolicy policy)
    {
        if (process.Id == Environment.ProcessId ||
            PermanentlyAllowedProcessNames.Contains(process.ProcessName) ||
            process.MainWindowHandle == IntPtr.Zero)
        {
            return true;
        }

        if (policy.AllowSupportedBrowsers && SupportedBrowserNames.Contains(process.ProcessName))
        {
            return true;
        }

        try
        {
            var packageFamily = PackageIdentity.ForProcess(process.Id);
            if (packageFamily is not null && policy.AllowedPackageFamilies.Contains(packageFamily))
            {
                return true;
            }

            var path = process.MainModule?.FileName;
            return path is not null && policy.AllowedPaths.Contains(Path.GetFullPath(path));
        }
        catch (Exception exception) when (exception is System.ComponentModel.Win32Exception or InvalidOperationException or NotSupportedException)
        {
            return true;
        }
    }

    public void Dispose() => timer.Dispose();

    private sealed record EnforcementPolicy(
        HashSet<string> AllowedPaths,
        HashSet<string> AllowedPackageFamilies,
        bool AllowSupportedBrowsers);

    private static class PackageIdentity
    {
        private const uint ProcessQueryLimitedInformation = 0x1000;
        private const int ErrorInsufficientBuffer = 122;
        private const int AppModelErrorNoPackage = 15700;

        public static string? ForProcess(int processId)
        {
            var handle = OpenProcess(ProcessQueryLimitedInformation, false, processId);
            if (handle == IntPtr.Zero)
            {
                return null;
            }

            try
            {
                uint length = 0;
                var result = GetPackageFamilyName(handle, ref length, null);
                if (result == AppModelErrorNoPackage ||
                    (result != ErrorInsufficientBuffer && result != 0) ||
                    length == 0)
                {
                    return null;
                }

                var familyName = new StringBuilder((int)length);
                result = GetPackageFamilyName(handle, ref length, familyName);
                return result == 0 ? familyName.ToString() : null;
            }
            finally
            {
                _ = CloseHandle(handle);
            }
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenProcess(
            uint desiredAccess,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
            int processId);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
        private static extern int GetPackageFamilyName(
            IntPtr process,
            ref uint packageFamilyNameLength,
            StringBuilder? packageFamilyName);

        [DllImport("kernel32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);
    }
}
