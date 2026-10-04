using System.Collections.ObjectModel;
using Monk.App.Services;

namespace Monk.App.ViewModels;

public sealed class SettingsViewModel : ObservableObject
{
    private readonly FocusSessionManager sessionManager;
    private string applicationQuery = "";
    private bool defaultBlockingEnabled;

    public SettingsViewModel(
        FocusSessionManager sessionManager,
        ApplicationCatalogService applicationCatalog)
    {
        this.sessionManager = sessionManager;
        var selectedIds = sessionManager.State.Settings.AlwaysAllowedApplications
            .Select(application => application.Id)
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        AllApplications = applicationCatalog.Discover()
            .Select(application => new SelectableApplication(application)
            {
                IsSelected = selectedIds.Contains(application.Id)
            })
            .ToList();
        Applications = new ObservableCollection<SelectableApplication>(AllApplications.Take(24));
        defaultBlockingEnabled = sessionManager.State.Settings.DefaultBlockingEnabled;
        ApplyCommand = new RelayCommand(Apply);
    }

    private List<SelectableApplication> AllApplications { get; }
    public ObservableCollection<SelectableApplication> Applications { get; }
    public RelayCommand ApplyCommand { get; }

    public bool DefaultBlockingEnabled
    {
        get => defaultBlockingEnabled;
        set => SetProperty(ref defaultBlockingEnabled, value);
    }

    public string ApplicationQuery
    {
        get => applicationQuery;
        set
        {
            if (!SetProperty(ref applicationQuery, value))
            {
                return;
            }

            var matches = AllApplications
                .Where(application =>
                    application.IsSelected ||
                    string.IsNullOrWhiteSpace(value) ||
                    application.DisplayName.Contains(value, StringComparison.CurrentCultureIgnoreCase) ||
                    application.Application.AppUserModelId?.Contains(value, StringComparison.OrdinalIgnoreCase) == true)
                .OrderByDescending(application => application.IsSelected)
                .ThenBy(application => application.DisplayName, StringComparer.CurrentCultureIgnoreCase)
                .Take(24)
                .ToArray();
            Applications.Clear();
            foreach (var application in matches)
            {
                Applications.Add(application);
            }
        }
    }

    public event EventHandler? Applied;

    private void Apply()
    {
        var selected = AllApplications
            .Where(application => application.IsSelected)
            .Select(application => application.Application)
            .ToArray();
        sessionManager.ConfigureDefaultBlocking(DefaultBlockingEnabled, selected);
        Applied?.Invoke(this, EventArgs.Empty);
    }
}
