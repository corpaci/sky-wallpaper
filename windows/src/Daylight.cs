// Port of Sources/wallframes/Daylight.swift; tests/daylight.sh checks both.

using System;
using System.Globalization;

/// Sunrise and sunset for one place and day, from NOAA's general solar
/// position equations: good to a minute or two outside the polar circles.
/// Times are local minutes after midnight for the given UTC offset.
///
/// The renderer needs every frame on its own minute, so the day is held
/// between 3 and 21 hours, centred on solar noon; `Note` says when the real
/// sky did something else (polar night or day, or a clamp).
sealed class Daylight
{
    public readonly int Sunrise, Sunset;
    public readonly string Note;

    public Daylight(double latitude, double longitude, int dayOfYear, int daysInYear, int utcOffset)
    {
        double g = 2 * Math.PI / daysInYear * (dayOfYear - 1);
        double eqTime = 229.18 * (0.000075 + 0.001868 * Math.Cos(g) - 0.032077 * Math.Sin(g)
                                  - 0.014615 * Math.Cos(2 * g) - 0.040849 * Math.Sin(2 * g));
        double decl = 0.006918 - 0.399912 * Math.Cos(g) + 0.070257 * Math.Sin(g) - 0.006758 * Math.Cos(2 * g)
            + 0.000907 * Math.Sin(2 * g) - 0.002697 * Math.Cos(3 * g) + 0.00148 * Math.Sin(3 * g);
        double lat = latitude * Math.PI / 180;
        double noon = 720 - 4 * longitude - eqTime + utcOffset;
        // 90.833°: the sun's centre below the horizon at first light, refraction included.
        double c = Math.Cos(90.833 * Math.PI / 180) / (Math.Cos(lat) * Math.Cos(decl)) - Math.Tan(lat) * Math.Tan(decl);

        double half;
        string note = null;
        if (c > 1) { half = 90; note = "polar night"; }
        else if (c < -1) { half = 630; note = "polar day"; }
        else half = 4 * Math.Acos(c) * 180 / Math.PI;
        if (half < 90 || half > 630)
        {
            half = Math.Min(Math.Max(half, 90), 630);
            note = "day held to " + (int)(half / 30) + " h";
        }
        int rise = (int)Math.Round(noon - half, MidpointRounding.AwayFromZero);
        int set = (int)Math.Round(noon + half, MidpointRounding.AwayFromZero);
        if (rise < 0) { set -= rise; rise = 0; if (note == null) note = "shifted into the day"; }
        if (set > 1439) { rise -= set - 1439; set = 1439; if (note == null) note = "shifted into the day"; }
        Sunrise = rise;
        Sunset = set;
        Note = note;
    }

    /// For a calendar date (`yyyy-MM-dd`), in this PC's time zone unless an
    /// offset in minutes is given. Null if the date doesn't parse.
    public static Daylight For(double latitude, double longitude, string date, int? utcOffset)
    {
        DateTime day;
        if (!DateTime.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out day)) return null;
        int offset = utcOffset.HasValue
            ? utcOffset.Value
            : (int)TimeZoneInfo.Local.GetUtcOffset(day.AddHours(12)).TotalMinutes;
        return new Daylight(latitude, longitude, day.DayOfYear, DateTime.IsLeapYear(day.Year) ? 366 : 365, offset);
    }
}
