using Monk.Core.Models;

namespace Monk.Core;

public static class FocusPolicyRules
{
    public static bool IsExpired(FocusPolicy policy, DateTimeOffset now) => policy.EndsAt <= now;

    public static bool CanEnd(FocusPolicy policy, DateTimeOffset now) => IsExpired(policy, now);

    public static FocusPolicy? ExtendExpired(
        FocusPolicy policy,
        TimeSpan duration,
        DateTimeOffset now)
    {
        if (duration <= TimeSpan.Zero || !IsExpired(policy, now))
        {
            return null;
        }
        return policy with { EndsAt = now.Add(duration) };
    }
}
