// The scheduled task, as Task Scheduler XML registered with schtasks.exe. It
// runs `sky-apply.exe tick`: daily at each switch time, at 00:05 (when tick
// renders the new day and rewrites these triggers), and to catch up at logon,
// unlock and wake. Low priority; never wakes the PC.

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Security;
using System.Text;

static class SkyTask
{
    public const string Name = "SkyWallpaper";

    // Resume from sleep, and leaving Modern Standby.
    const string WakeQuery = "<QueryList><Query Id=\"0\" Path=\"System\">"
        + "<Select Path=\"System\">*[System[Provider[@Name='Microsoft-Windows-Power-Troubleshooter'] and EventID=1]]</Select>"
        + "<Select Path=\"System\">*[System[Provider[@Name='Microsoft-Windows-Kernel-Power'] and EventID=507]]</Select>"
        + "</Query></QueryList>";

    public static string Xml(string date, IEnumerable<int> minutes, string user, string exe, bool wake)
    {
        string u = SecurityElement.Escape(user);
        var x = new StringBuilder();
        x.AppendLine("<?xml version=\"1.0\" encoding=\"UTF-16\"?>");
        x.AppendLine("<Task version=\"1.2\" xmlns=\"http://schemas.microsoft.com/windows/2004/02/mit/task\">");
        x.AppendLine("  <RegistrationInfo><Description>Sets the sky wallpaper frame for the time of day, then exits.</Description></RegistrationInfo>");
        x.AppendLine("  <Triggers>");
        foreach (int m in minutes.Concat(new[] { 5 }).Distinct().OrderBy(m => m))
        {
            x.AppendFormat("    <CalendarTrigger><StartBoundary>{0}T{1:D2}:{2:D2}:00</StartBoundary><ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay></CalendarTrigger>",
                date, m / 60, m % 60).AppendLine();
        }
        x.AppendFormat("    <LogonTrigger><UserId>{0}</UserId><Delay>PT30S</Delay></LogonTrigger>", u).AppendLine();
        x.AppendFormat("    <SessionStateChangeTrigger><StateChange>SessionUnlock</StateChange><UserId>{0}</UserId></SessionStateChangeTrigger>", u).AppendLine();
        if (wake) x.AppendFormat("    <EventTrigger><Subscription>{0}</Subscription></EventTrigger>", SecurityElement.Escape(WakeQuery)).AppendLine();
        x.AppendLine("  </Triggers>");
        x.AppendFormat("  <Principals><Principal id=\"Author\"><UserId>{0}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal></Principals>", u).AppendLine();
        x.AppendLine("  <Settings>");
        x.AppendLine("    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>");
        x.AppendLine("    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>");
        x.AppendLine("    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>");
        x.AppendLine("    <StartWhenAvailable>true</StartWhenAvailable>");
        x.AppendLine("    <WakeToRun>false</WakeToRun>");
        x.AppendLine("    <ExecutionTimeLimit>PT15M</ExecutionTimeLimit>");
        x.AppendLine("    <Priority>7</Priority>");
        x.AppendLine("  </Settings>");
        x.AppendFormat("  <Actions Context=\"Author\"><Exec><Command>{0}</Command><Arguments>tick</Arguments></Exec></Actions>", SecurityElement.Escape(exe)).AppendLine();
        x.AppendLine("</Task>");
        return x.ToString();
    }

    /// Creates or replaces the task. False with the reason if schtasks refuses.
    public static bool Register(string xml, out string error)
    {
        string file = Path.GetTempFileName();
        try
        {
            File.WriteAllText(file, xml, Encoding.Unicode);
            var start = new ProcessStartInfo("schtasks.exe", "/Create /TN " + Name + " /XML \"" + file + "\" /F")
            {
                UseShellExecute = false,
                CreateNoWindow = true,  // no console flash from the windowless build
                RedirectStandardOutput = true,
                RedirectStandardError = true,
            };
            using (Process p = Process.Start(start))
            {
                string output = p.StandardOutput.ReadToEnd() + p.StandardError.ReadToEnd();
                p.WaitForExit();
                error = output.Trim();
                return p.ExitCode == 0;
            }
        }
        finally
        {
            File.Delete(file);
        }
    }
}
