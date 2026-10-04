using Monk.Core.Models;

namespace Monk.App.ViewModels;

public sealed class SelectableApplication(ApplicationDescriptor application) : ObservableObject
{
    private bool isSelected;

    public ApplicationDescriptor Application { get; } = application;
    public string DisplayName => Application.DisplayName;
    public string ExecutablePath => Application.ExecutablePath;
    public string Detail => Application.IsPackaged
        ? "Microsoft Store app"
        : Application.ExecutablePath;

    public bool IsSelected
    {
        get => isSelected;
        set => SetProperty(ref isSelected, value);
    }
}
