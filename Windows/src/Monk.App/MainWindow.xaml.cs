using System.ComponentModel;
using System.Windows;
using System.Windows.Input;
using Monk.App.ViewModels;

namespace Monk.App;

public partial class MainWindow : Window
{
    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
    }

    public event EventHandler? SettingsRequested;

    private void OnDragWindow(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void OnHide(object sender, RoutedEventArgs e) => Hide();

    private void OnSettings(object sender, RoutedEventArgs e) => SettingsRequested?.Invoke(this, EventArgs.Empty);

    protected override void OnClosing(CancelEventArgs e)
    {
        e.Cancel = true;
        Hide();
    }
}
