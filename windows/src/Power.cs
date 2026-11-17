// Whether the PC runs on battery, and whether battery saver is on, so a tick
// can hold back the day's render as config.txt asks.

using System.Runtime.InteropServices;

static class Power
{
    [StructLayout(LayoutKind.Sequential)]
    struct SystemPowerStatus
    {
        public byte ACLineStatus;      // 0 battery, 1 mains, 255 unknown
        public byte BatteryFlag;
        public byte BatteryLifePercent;
        public byte SystemStatusFlag;  // 1 when battery saver is on (Windows 10+)
        public int BatteryLifeTime;
        public int BatteryFullLifeTime;
    }

    [DllImport("kernel32.dll")]
    static extern bool GetSystemPowerStatus(out SystemPowerStatus status);

    /// On battery, as far as Windows knows; a desktop PC never is.
    public static bool OnBattery()
    {
        SystemPowerStatus s;
        return GetSystemPowerStatus(out s) && s.ACLineStatus == 0;
    }

    public static bool Saver()
    {
        SystemPowerStatus s;
        return GetSystemPowerStatus(out s) && s.SystemStatusFlag == 1;
    }
}
