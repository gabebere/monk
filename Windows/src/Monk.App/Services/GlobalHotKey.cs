using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace Monk.App.Services;

public sealed class GlobalHotKey : IDisposable
{
    public const uint ModAlt = 0x0001;
    private const int HotKeyId = 0x4D4F4E4B;
    private const int WmHotKey = 0x0312;

    private readonly IntPtr handle;
    private readonly HwndSource source;
    private readonly Action action;

    public GlobalHotKey(Window window, uint modifiers, uint virtualKey, Action action)
    {
        handle = new WindowInteropHelper(window).Handle;
        source = HwndSource.FromHwnd(handle) ?? throw new InvalidOperationException("Window handle unavailable.");
        this.action = action;
        source.AddHook(WndProc);
        _ = RegisterHotKey(handle, HotKeyId, modifiers, virtualKey);
    }

    private IntPtr WndProc(IntPtr hwnd, int message, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (message == WmHotKey && wParam.ToInt32() == HotKeyId)
        {
            action();
            handled = true;
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        _ = UnregisterHotKey(handle, HotKeyId);
        source.RemoveHook(WndProc);
    }

    [DllImport("user32.dll")]
    private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint virtualKey);

    [DllImport("user32.dll")]
    private static extern bool UnregisterHotKey(IntPtr hWnd, int id);
}
