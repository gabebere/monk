using System.Windows;
using Monk.App.ViewModels;

namespace Monk.App;

public partial class SettingsWindow : Window
{
    public SettingsWindow(SettingsViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
        viewModel.Applied += (_, _) => Close();
    }
}
