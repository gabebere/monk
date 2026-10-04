using System.Collections.ObjectModel;
using Monk.App.Services;
using Monk.Core.Models;

namespace Monk.App.ViewModels;

public sealed class MainViewModel : ObservableObject
{
    private readonly FocusSessionManager sessionManager;
    private readonly List<SelectableApplication> allApplications;
    private string intention = "";
    private string hours = "";
    private string minutes = "30";
    private string applicationQuery = "";
    private string domains = "";
    private string lastBlockedActivity = "";

    public MainViewModel(
        FocusSessionManager sessionManager,
        ApplicationCatalogService applicationCatalog)
    {
        this.sessionManager = sessionManager;
        allApplications = applicationCatalog.Discover()
            .Select(application => new SelectableApplication(application))
            .ToList();
        Applications = [];

        BeginCommand = new RelayCommand(Begin, CanBegin);
        ExtendFifteenCommand = new RelayCommand(() => sessionManager.Extend(TimeSpan.FromMinutes(15)));
        ExtendThirtyCommand = new RelayCommand(() => sessionManager.Extend(TimeSpan.FromMinutes(30)));
        ExtendHourCommand = new RelayCommand(() => sessionManager.Extend(TimeSpan.FromHours(1)));
        EndCommand = new RelayCommand(sessionManager.EndExpired);

        foreach (var application in allApplications)
        {
            application.PropertyChanged += (_, _) =>
            {
                BeginCommand.RaiseCanExecuteChanged();
                RefreshApplications();
            };
        }
        sessionManager.StateChanged += (_, _) => RefreshSession();
        RefreshSession();
    }

    public ObservableCollection<SelectableApplication> Applications { get; }
    public RelayCommand BeginCommand { get; }
    public RelayCommand ExtendFifteenCommand { get; }
    public RelayCommand ExtendThirtyCommand { get; }
    public RelayCommand ExtendHourCommand { get; }
    public RelayCommand EndCommand { get; }

    public string Intention
    {
        get => intention;
        set
        {
            if (SetProperty(ref intention, value))
            {
                BeginCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string Hours
    {
        get => hours;
        set
        {
            if (SetProperty(ref hours, SanitizeNumber(value, 12)))
            {
                BeginCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string Minutes
    {
        get => minutes;
        set
        {
            if (SetProperty(ref minutes, SanitizeNumber(value, 59)))
            {
                BeginCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string ApplicationQuery
    {
        get => applicationQuery;
        set
        {
            if (SetProperty(ref applicationQuery, value))
            {
                RefreshApplications();
            }
        }
    }

    public string Domains
    {
        get => domains;
        set
        {
            if (SetProperty(ref domains, value))
            {
                BeginCommand.RaiseCanExecuteChanged();
            }
        }
    }

    public string LastBlockedActivity
    {
        get => lastBlockedActivity;
        set => SetProperty(ref lastBlockedActivity, value);
    }

    public bool HasBlockedActivity => !string.IsNullOrWhiteSpace(LastBlockedActivity);
    public bool HasVisibleApplications => Applications.Count > 0;
    public bool IsActive => sessionManager.State.ActivePolicy is not null;
    public bool IsAwaitingDecision => sessionManager.IsAwaitingDecision;
    public string ActiveIntention => sessionManager.State.ActivePolicy?.Intention ?? "";
    public IReadOnlyList<string> ActiveApplications =>
        sessionManager.State.ActivePolicy?.AllowedApplications.Select(app => app.DisplayName).ToArray() ?? [];

    public string RemainingTime
    {
        get
        {
            var remaining = sessionManager.RemainingTime;
            return remaining.TotalHours >= 1
                ? $"{(int)remaining.TotalHours}:{remaining.Minutes:00}:{remaining.Seconds:00}"
                : $"{remaining.Minutes:00}:{remaining.Seconds:00}";
        }
    }

    private void Begin()
    {
        var selected = allApplications
            .Where(application => application.IsSelected)
            .Select(application => application.Application)
            .ToArray();
        sessionManager.Start(
            Intention,
            TimeSpan.FromMinutes(DurationMinutes),
            selected,
            SplitDomains());
    }

    private bool CanBegin() =>
        !string.IsNullOrWhiteSpace(Intention) &&
        DurationMinutes > 0 &&
        (allApplications.Any(application => application.IsSelected) || SplitDomains().Any());

    private int DurationMinutes =>
        (int.TryParse(Hours, out var hourValue) ? hourValue * 60 : 0) +
        (int.TryParse(Minutes, out var minuteValue) ? minuteValue : 0);

    private IEnumerable<string> SplitDomains() => Domains.Split(
        [',', ';', '\n', '\r'],
        StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries);

    private void RefreshApplications()
    {
        var hasQuery = !string.IsNullOrWhiteSpace(ApplicationQuery);
        var matches = allApplications
            .Where(application =>
                application.IsSelected ||
                (hasQuery && (
                    application.DisplayName.Contains(ApplicationQuery, StringComparison.CurrentCultureIgnoreCase) ||
                    application.Application.AppUserModelId?.Contains(ApplicationQuery, StringComparison.OrdinalIgnoreCase) == true)))
            .OrderByDescending(application => application.IsSelected)
            .ThenBy(application => application.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .Take(18)
            .ToArray();
        Applications.Clear();
        foreach (var application in matches)
        {
            Applications.Add(application);
        }
        OnPropertyChanged(nameof(HasVisibleApplications));
    }

    private void RefreshSession()
    {
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            OnPropertyChanged(nameof(IsActive));
            OnPropertyChanged(nameof(IsAwaitingDecision));
            OnPropertyChanged(nameof(ActiveIntention));
            OnPropertyChanged(nameof(ActiveApplications));
            OnPropertyChanged(nameof(RemainingTime));
            OnPropertyChanged(nameof(HasBlockedActivity));
        });
    }

    private static string SanitizeNumber(string rawValue, int maximum)
    {
        var digits = new string(rawValue.Where(char.IsAsciiDigit).Take(2).ToArray());
        return int.TryParse(digits, out var value) ? Math.Min(value, maximum).ToString() : "";
    }
}
