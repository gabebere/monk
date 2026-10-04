using Monk.Core;
using Monk.Core.Models;

namespace Monk.App.Services;

public sealed class FocusSessionManager : IDisposable
{
    private readonly StateStore stateStore;
    private readonly ProcessGuardian guardian;
    private readonly System.Threading.Timer timer;
    private readonly object gate = new();
    private MonkState state;
    private bool expiryRaised;

    public FocusSessionManager(ProcessGuardian guardian, StateStore? stateStore = null)
    {
        this.guardian = guardian;
        this.stateStore = stateStore ?? new StateStore();
        state = this.stateStore.Load();
        guardian.BlockedApplication += (_, name) => BlockedApplication?.Invoke(this, name);
        ApplyGuardian();
        timer = new System.Threading.Timer(_ => Tick(), null, TimeSpan.Zero, TimeSpan.FromSeconds(1));
    }

    public event EventHandler? StateChanged;
    public event EventHandler? SessionExpired;
    public event EventHandler<string>? BlockedApplication;

    public MonkState State
    {
        get
        {
            lock (gate)
            {
                return state;
            }
        }
    }

    public bool IsAwaitingDecision =>
        State.ActivePolicy is { } policy && FocusPolicyRules.IsExpired(policy, DateTimeOffset.Now);

    public bool PreventsTermination => State.ActivePolicy is not null || State.Settings.DefaultBlockingEnabled;

    public TimeSpan RemainingTime => State.ActivePolicy is { } policy
        ? TimeSpan.FromSeconds(Math.Max(0, (policy.EndsAt - DateTimeOffset.Now).TotalSeconds))
        : TimeSpan.Zero;

    public void Start(
        string intention,
        TimeSpan duration,
        IReadOnlyList<ApplicationDescriptor> allowedApplications,
        IEnumerable<string> allowedDomains)
    {
        lock (gate)
        {
            if (state.ActivePolicy is not null)
            {
                return;
            }

            var policy = FocusPolicy.Create(
                intention,
                duration,
                allowedApplications,
                allowedDomains);
            state = state with { ActivePolicy = policy, Revision = state.Revision + 1 };
            PersistLocked();
            expiryRaised = false;
        }
        ApplyGuardian();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void Extend(TimeSpan duration)
    {
        lock (gate)
        {
            if (state.ActivePolicy is not { } policy ||
                FocusPolicyRules.ExtendExpired(policy, duration, DateTimeOffset.Now) is not { } extendedPolicy)
            {
                return;
            }

            state = state with
            {
                ActivePolicy = extendedPolicy,
                Revision = state.Revision + 1
            };
            PersistLocked();
            expiryRaised = false;
        }
        ApplyGuardian();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void EndExpired()
    {
        lock (gate)
        {
            if (state.ActivePolicy is not { } policy ||
                !FocusPolicyRules.CanEnd(policy, DateTimeOffset.Now))
            {
                return;
            }
            state = state with { ActivePolicy = null, Revision = state.Revision + 1 };
            PersistLocked();
            expiryRaised = false;
        }
        ApplyGuardian();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    public void ConfigureDefaultBlocking(
        bool enabled,
        IReadOnlyList<ApplicationDescriptor> alwaysAllowedApplications)
    {
        lock (gate)
        {
            if (state.ActivePolicy is not null)
            {
                return;
            }
            state = state with
            {
                Settings = new MonkSettings(enabled, alwaysAllowedApplications),
                Revision = state.Revision + 1
            };
            PersistLocked();
        }
        ApplyGuardian();
        StateChanged?.Invoke(this, EventArgs.Empty);
    }

    private void Tick()
    {
        var raiseExpiry = false;
        lock (gate)
        {
            if (state.ActivePolicy is { } policy &&
                FocusPolicyRules.IsExpired(policy, DateTimeOffset.Now) &&
                !expiryRaised)
            {
                expiryRaised = true;
                raiseExpiry = true;
            }
        }
        StateChanged?.Invoke(this, EventArgs.Empty);
        if (raiseExpiry)
        {
            SessionExpired?.Invoke(this, EventArgs.Empty);
        }
    }

    private void ApplyGuardian()
    {
        var current = State;
        if (current.ActivePolicy is { } policy)
        {
            var applications = current.Settings.DefaultBlockingEnabled
                ? policy.AllowedApplications.Concat(current.Settings.AlwaysAllowedApplications)
                : policy.AllowedApplications;
            guardian.Apply(true, applications, policy.AllowedDomains.Count > 0);
        }
        else
        {
            guardian.Apply(
                current.Settings.DefaultBlockingEnabled,
                current.Settings.AlwaysAllowedApplications,
                false);
        }
    }

    private void PersistLocked() => stateStore.Save(state);

    public void Dispose()
    {
        timer.Dispose();
        guardian.Dispose();
    }
}
