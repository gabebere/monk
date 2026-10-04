using System.Globalization;

namespace Monk.Core;

public sealed class DomainAllowlist
{
    private static readonly HashSet<string> SafeSchemes = new(StringComparer.OrdinalIgnoreCase)
    {
        "about", "brave", "chrome", "data", "edge", "file", "extension"
    };

    private readonly IReadOnlyList<string> domains;

    public DomainAllowlist(IEnumerable<string> domains)
    {
        this.domains = NormalizeMany(domains);
    }

    public bool Allows(string rawUrl)
    {
        if (string.IsNullOrWhiteSpace(rawUrl))
        {
            return true;
        }

        if (rawUrl.StartsWith("view-source:", StringComparison.OrdinalIgnoreCase))
        {
            return Allows(rawUrl["view-source:".Length..]);
        }

        if (rawUrl.StartsWith("blob:", StringComparison.OrdinalIgnoreCase))
        {
            return Allows(rawUrl["blob:".Length..]);
        }

        if (!Uri.TryCreate(rawUrl, UriKind.Absolute, out var uri))
        {
            return false;
        }

        if (uri.Scheme is not ("http" or "https"))
        {
            return SafeSchemes.Contains(uri.Scheme);
        }

        var host = uri.IdnHost.Trim('.').ToLowerInvariant();
        return domains.Any(domain =>
            host.Equals(domain, StringComparison.OrdinalIgnoreCase) ||
            host.EndsWith('.' + domain, StringComparison.OrdinalIgnoreCase));
    }

    public static string? Normalize(string rawValue)
    {
        var candidate = rawValue.Trim();
        if (candidate.Length == 0)
        {
            return null;
        }

        if (!candidate.Contains("://", StringComparison.Ordinal))
        {
            candidate = "https://" + candidate;
        }

        if (!Uri.TryCreate(candidate, UriKind.Absolute, out var uri) ||
            string.IsNullOrWhiteSpace(uri.Host))
        {
            return null;
        }

        try
        {
            var host = new IdnMapping().GetAscii(uri.Host).Trim('.').ToLowerInvariant();
            return host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;
        }
        catch (ArgumentException)
        {
            return null;
        }
    }

    public static IReadOnlyList<string> NormalizeMany(IEnumerable<string> values) =>
        values
            .Select(Normalize)
            .Where(value => value is not null)
            .Select(value => value!)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Order(StringComparer.OrdinalIgnoreCase)
            .ToArray();
}
