using Monk.Core;
using Monk.Core.Models;

var tests = new (string Name, Action Run)[]
{
    ("allows exact domains and subdomains", () =>
    {
        var allowlist = new DomainAllowlist(["netflix.com", "www.openai.com"]);
        Assert(allowlist.Allows("https://netflix.com/watch/1"));
        Assert(allowlist.Allows("https://chat.openai.com"));
        Assert(!allowlist.Allows("https://notnetflix.com"));
    }),
    ("normalizes domain inputs", () =>
    {
        Equal("netflix.com", DomainAllowlist.Normalize(" HTTPS://WWW.Netflix.com/watch/1 "));
        Equal(null, DomainAllowlist.Normalize("not a website"));
    }),
    ("keeps browser internal pages safe", () =>
    {
        var allowlist = new DomainAllowlist([]);
        Assert(allowlist.Allows("chrome://newtab"));
        Assert(!allowlist.Allows("view-source:https://example.com"));
    }),
    ("creates the requested deadline", () =>
    {
        var start = DateTimeOffset.FromUnixTimeSeconds(10_000);
        var policy = FocusPolicy.Create("Build Monk", TimeSpan.FromMinutes(75), [], [], start);
        Equal(TimeSpan.FromMinutes(75), policy.EndsAt - policy.StartedAt);
    }),
    ("creates stable packaged application identities", () =>
    {
        var application = ApplicationDescriptor.FromPackagedApplication(
            "Notepad",
            "Microsoft.WindowsNotepad_8wekyb3d8bbwe!App");
        Assert(application.IsPackaged);
        Equal("Microsoft.WindowsNotepad_8wekyb3d8bbwe", application.PackageFamilyName);
        Equal("package:MICROSOFT.WINDOWSNOTEPAD_8WEKYB3D8BBWE!APP", application.Id);
    }),
    ("does not permit an early end", () =>
    {
        var start = DateTimeOffset.FromUnixTimeSeconds(10_000);
        var policy = FocusPolicy.Create("Build Monk", TimeSpan.FromMinutes(30), [], [], start);
        Assert(!FocusPolicyRules.CanEnd(policy, start.AddMinutes(29)));
        Assert(FocusPolicyRules.CanEnd(policy, start.AddMinutes(30)));
        Equal(null, FocusPolicyRules.ExtendExpired(policy, TimeSpan.FromMinutes(15), start.AddMinutes(29)));
    }),
    ("persists browser policy without the intention", () =>
    {
        var testRoot = Path.Combine(Path.GetTempPath(), "MonkSmokeTests", Guid.NewGuid().ToString("N"));
        try
        {
            var store = new StateStore(testRoot);
            var policy = FocusPolicy.Create("Private intention", TimeSpan.FromMinutes(15), [], ["docs.microsoft.com"]);
            store.Save(new MonkState(policy, MonkSettings.Default, 4));
            var browserPolicy = store.LoadBrowserPolicy();
            Assert(browserPolicy.Enforcing);
            Equal(4L, browserPolicy.Revision);
            Equal("docs.microsoft.com", browserPolicy.AllowedDomains.Single());
        }
        finally
        {
            if (Directory.Exists(testRoot))
            {
                Directory.Delete(testRoot, true);
            }
        }
    })
};

var failures = 0;
foreach (var test in tests)
{
    try
    {
        test.Run();
        Console.WriteLine($"PASS {test.Name}");
    }
    catch (Exception exception)
    {
        failures++;
        Console.Error.WriteLine($"FAIL {test.Name}: {exception.Message}");
    }
}

return failures == 0 ? 0 : 1;

static void Assert(bool condition)
{
    if (!condition)
    {
        throw new InvalidOperationException("Assertion failed.");
    }
}

static void Equal<T>(T expected, T actual)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"Expected {expected}; received {actual}.");
    }
}
