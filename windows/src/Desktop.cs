// The Windows wallpaper through IDesktopWallpaper (shobjidl.h, Windows 8+):
// one image per monitor, set and read back by monitor id. Interface methods
// are declared in vtable order, only as far as the last one used.

using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;

[ComImport, Guid("B92B56A9-8B55-4E14-9A89-0199BBB6F93B"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IDesktopWallpaper
{
    void SetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID, [MarshalAs(UnmanagedType.LPWStr)] string wallpaper);
    [return: MarshalAs(UnmanagedType.LPWStr)]
    string GetWallpaper([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
    [return: MarshalAs(UnmanagedType.LPWStr)]
    string GetMonitorDevicePathAt(uint monitorIndex);
    uint GetMonitorDevicePathCount();
    NativeRect GetMonitorRECT([MarshalAs(UnmanagedType.LPWStr)] string monitorID);
    void SetBackgroundColor(uint color);
    uint GetBackgroundColor();
    void SetPosition(int position);
    int GetPosition();
}

[ComImport, Guid("C2CF3110-460E-4fc1-B9D0-8A1C0C9CC4BD")]
class DesktopWallpaperClass { }

[StructLayout(LayoutKind.Sequential)]
struct NativeRect { public int Left, Top, Right, Bottom; }

struct Monitor
{
    public string Id;
    public int Width, Height;
}

static class Desktop
{
    const int Fill = 4;  // DWPOS_FILL: frames are rendered at native size, so Fill is 1:1

    [DllImport("user32.dll")]
    static extern bool SetProcessDpiAwarenessContext(IntPtr value);
    [DllImport("user32.dll")]
    static extern bool SetProcessDPIAware();

    /// Monitor rectangles come back in physical pixels only for a DPI-aware
    /// process; call before any monitor query.
    public static void BeDpiAware()
    {
        try
        {
            if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return;  // per-monitor v2, Windows 10 1703+
        }
        catch (EntryPointNotFoundException) { }
        SetProcessDPIAware();
    }

    static IDesktopWallpaper Open() { return (IDesktopWallpaper)new DesktopWallpaperClass(); }

    /// Active monitors. Ids of disconnected ones are listed too but have no
    /// rectangle; they are skipped.
    public static List<Monitor> Monitors()
    {
        var dw = Open();
        var list = new List<Monitor>();
        uint n = dw.GetMonitorDevicePathCount();
        for (uint i = 0; i < n; i++)
        {
            string id = dw.GetMonitorDevicePathAt(i);
            NativeRect r;
            try { r = dw.GetMonitorRECT(id); }
            catch (COMException) { continue; }
            Monitor m;
            m.Id = id;
            m.Width = r.Right - r.Left;
            m.Height = r.Bottom - r.Top;
            if (m.Width > 0 && m.Height > 0) list.Add(m);
        }
        return list;
    }

    /// Set each monitor to the frame for `minute` (local), from the frame set
    /// rendered at its size, or the closest aspect if it has none. Monitors
    /// already showing the right frame are left alone.
    public static List<string> Apply(List<FrameSet> sets, int minute)
    {
        if (sets.Count == 0) throw new InvalidOperationException("no frame sets to apply");
        var dw = Open();
        var report = new List<string>();
        foreach (Monitor m in Monitors())
        {
            FrameSet set = FrameSet.Closest(sets, m.Width, m.Height);
            string frame = set.FrameAt(minute);
            string current = "";
            try { current = dw.GetWallpaper(m.Id) ?? ""; }
            catch (COMException) { }
            bool same = string.Equals(current, frame, StringComparison.OrdinalIgnoreCase);
            if (!same) dw.SetWallpaper(m.Id, frame);
            report.Add(string.Format("{0}x{1}: {2}{3}", m.Width, m.Height, Path.GetFileName(frame), same ? " (unchanged)" : ""));
        }
        if (dw.GetPosition() != Fill) dw.SetPosition(Fill);
        return report;
    }

    /// Current wallpapers and position, one `id<TAB>path` per line, for
    /// `Restore` to put back on uninstall.
    public static void Save(string file)
    {
        var dw = Open();
        var lines = new List<string> { "position\t" + dw.GetPosition() };
        foreach (Monitor m in Monitors())
        {
            string current = "";
            try { current = dw.GetWallpaper(m.Id) ?? ""; }
            catch (COMException) { }
            lines.Add(m.Id + "\t" + current);
        }
        File.WriteAllLines(file, lines);
    }

    public static List<string> Restore(string file)
    {
        var dw = Open();
        var report = new List<string>();
        var present = new HashSet<string>(Monitors().Select(m => m.Id), StringComparer.OrdinalIgnoreCase);
        foreach (string line in File.ReadAllLines(file))
        {
            string[] f = line.Split('\t');
            if (f.Length != 2) continue;
            int position;
            if (f[0] == "position" && int.TryParse(f[1], out position)) { dw.SetPosition(position); continue; }
            if (!present.Contains(f[0])) { report.Add("monitor gone: " + f[0]); continue; }
            if (f[1] == "" || !File.Exists(f[1])) { report.Add("no file to restore for " + f[0]); continue; }
            dw.SetWallpaper(f[0], f[1]);
            report.Add("restored " + f[1]);
        }
        return report;
    }
}
