using System.Drawing;
using System.Windows;
using Forms = System.Windows.Forms;
using Monk.App.Services;
using Monk.App.ViewModels;

namespace Monk.App;

public partial class App : System.Windows.Application
{
    private FocusSessionManager? sessionManager;
    private MainWindow? mainWindow;
    private Forms.NotifyIcon? trayIcon;
    private GlobalHotKey? hotKey;
    private Mutex? singleInstanceMutex;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        singleInstanceMutex = new Mutex(true, "Monk.Windows.SingleInstance", out var createdNew);
        if (!createdNew)
        {
            Shutdown();
            return;
        }

        var catalog = new ApplicationCatalogService();
        var guardian = new ProcessGuardian();
        sessionManager = new FocusSessionManager(guardian);
        var viewModel = new MainViewModel(sessionManager, catalog);

        mainWindow = new MainWindow(viewModel);
        MainWindow = mainWindow;
        mainWindow.SettingsRequested += (_, _) => ShowSettings();
        mainWindow.SourceInitialized += (_, _) =>
        {
            hotKey = new GlobalHotKey(mainWindow, GlobalHotKey.ModAlt, 0x20, ToggleWindow);
        };

        var iconStream = GetResourceStream(new Uri("pack://application:,,,/Assets/monk.ico"))?.Stream;
        trayIcon = new Forms.NotifyIcon
        {
            Icon = iconStream is null ? SystemIcons.Shield : new Icon(iconStream),
            Text = "Monk",
            Visible = true,
            ContextMenuStrip = BuildTrayMenu()
        };
        trayIcon.DoubleClick += (_, _) => ShowWindow();

        sessionManager.BlockedApplication += (_, name) =>
            Dispatcher.Invoke(() =>
            {
                viewModel.LastBlockedActivity = $"Blocked {name}";
                ShowWindow();
            });
        sessionManager.SessionExpired += (_, _) => Dispatcher.Invoke(ShowWindow);

        ShowWindow();
    }

    private Forms.ContextMenuStrip BuildTrayMenu()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Items.Add("Open Monk", null, (_, _) => ShowWindow());
        menu.Items.Add("Settings", null, (_, _) => ShowSettings());
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add("Quit Monk", null, (_, _) => RequestExit());
        return menu;
    }

    private void ToggleWindow()
    {
        if (mainWindow?.IsVisible == true)
        {
            mainWindow.Hide();
        }
        else
        {
            ShowWindow();
        }
    }

    private void ShowWindow()
    {
        if (mainWindow is null)
        {
            return;
        }

        mainWindow.Show();
        mainWindow.Activate();
        mainWindow.Topmost = true;
        mainWindow.Topmost = false;
        mainWindow.Focus();
    }

    private void ShowSettings()
    {
        if (sessionManager is null)
        {
            return;
        }

        if (sessionManager.State.ActivePolicy is not null)
        {
            ShowWindow();
            System.Windows.MessageBox.Show(
                "Default access cannot change while Monk is enforcing a commitment.",
                "Monk",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        var window = new SettingsWindow(new SettingsViewModel(
            sessionManager,
            new ApplicationCatalogService()))
        {
            Owner = mainWindow
        };
        window.ShowDialog();
    }

    private void RequestExit()
    {
        if (sessionManager?.PreventsTermination == true)
        {
            ShowWindow();
            return;
        }

        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        hotKey?.Dispose();
        trayIcon?.Dispose();
        sessionManager?.Dispose();
        singleInstanceMutex?.Dispose();
        base.OnExit(e);
    }
}
