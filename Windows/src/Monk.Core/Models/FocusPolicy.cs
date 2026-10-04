namespace Monk.Core.Models;

public sealed record FocusPolicy(
    Guid Id,
    string Intention,
    DateTimeOffset StartedAt,
    DateTimeOffset EndsAt,
    IReadOnlyList<ApplicationDescriptor> AllowedApplications,
    IReadOnlyList<string> AllowedDomains)
{
    public static FocusPolicy Create(
        string intention,
        TimeSpan duration,
        IReadOnlyList<ApplicationDescriptor> allowedApplications,
        IEnumerable<string> allowedDomains,
        DateTimeOffset? now = null)
    {
        if (string.IsNullOrWhiteSpace(intention))
        {
            throw new ArgumentException("An intention is required.", nameof(intention));
        }

        if (duration <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(duration));
        }

        var startedAt = now ?? DateTimeOffset.Now;
        return new FocusPolicy(
            Guid.NewGuid(),
            intention.Trim(),
            startedAt,
            startedAt.Add(duration),
            allowedApplications,
            DomainAllowlist.NormalizeMany(allowedDomains));
    }
}
