using System.Text.Json;
using Monk.Core.Models;

namespace Monk.Core;

public sealed class StateStore
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    public StateStore(string? rootDirectory = null)
    {
        RootDirectory = rootDirectory ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Monk");
    }

    public string RootDirectory { get; }

    public string StatePath => Path.Combine(RootDirectory, "state.json");

    public MonkState Load()
    {
        try
        {
            if (!File.Exists(StatePath))
            {
                return MonkState.Empty;
            }

            var json = File.ReadAllText(StatePath);
            return JsonSerializer.Deserialize<MonkState>(json, JsonOptions) ?? MonkState.Empty;
        }
        catch (JsonException)
        {
            return MonkState.Empty;
        }
        catch (IOException)
        {
            return MonkState.Empty;
        }
    }

    public void Save(MonkState state)
    {
        Directory.CreateDirectory(RootDirectory);
        var temporaryPath = StatePath + ".new";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(state, JsonOptions));
        File.Move(temporaryPath, StatePath, true);
    }

    public BrowserPolicy LoadBrowserPolicy()
    {
        var state = Load();
        if (state.ActivePolicy is null)
        {
            return new BrowserPolicy(false, [], state.Revision);
        }

        return new BrowserPolicy(
            state.ActivePolicy.AllowedDomains.Count > 0,
            state.ActivePolicy.AllowedDomains,
            state.Revision);
    }
}
