// C# twin of main.swift: the same sky quantities, printed the same way, so
// tests/astronomy.sh can check that the two agree.

using System;
using System.Globalization;
using System.Linq;

static class Check
{
    static Ephemeris At(int y, int m, int d, double hour, double lat = 0, double lon = 0)
    {
        return new Ephemeris(lat, lon, Ephemeris.DayNumber(y, m, d, hour * 60));
    }

    static Planet Body(Ephemeris e, string name) { return e.Planets.First(p => p.Name == name); }

    static void Say(string name, double v) { Console.WriteLine(name + " " + v.ToString("F3", CultureInfo.InvariantCulture)); }

    /// The extreme of f over hourly steps from day0 for `days` days, and when:
    /// the day of the month, with the hour as a fraction.
    static double[] Extreme(int y, int m, int day0, int days, bool max, Func<Ephemeris, double> f)
    {
        double best = max ? -1e9 : 1e9, when = 0;
        for (int h = 0; h < days * 24; h++)
        {
            double v = f(At(y, m, day0, h));
            if (max ? v > best : v < best) { best = v; when = day0 + h / 24.0; }
        }
        return new[] { best, when };
    }

    static double SunAlt(Ephemeris e) { return Math.Asin(e.Sun.Z) * 180 / Math.PI; }

    static void Main()
    {
        Ephemeris dallas = At(2024, 4, 8, 18.7, 32.78, -96.80);
        Say("solar-eclipse-dallas-sep", dallas.Sun.Angle(dallas.Moon));
        Say("solar-eclipse-dallas-phase", dallas.MoonPhaseAngle);
        Ephemeris lunar = At(2025, 9, 7, 18 + 11.0 / 60);
        Say("lunar-eclipse-from-antisun", 180 - lunar.Sun.Angle(lunar.MoonFromCenter));
        Say("lunar-eclipse-lit", lunar.MoonLit);
        double[] js = Extreme(2020, 12, 19, 5, false, e => Body(e, "Jupiter").Direction.Angle(Body(e, "Saturn").Direction));
        Say("jupiter-saturn-min-sep", js[0]); Say("jupiter-saturn-day", js[1]);
        double[] vj = Extreme(2023, 3, -2, 6, false, e => Body(e, "Venus").Direction.Angle(Body(e, "Jupiter").Direction));
        Say("venus-jupiter-min-sep", vj[0]); Say("venus-jupiter-day", vj[1]);
        double[] me = Extreme(2024, 3, 14, 20, true, e => Body(e, "Mercury").Direction.Angle(e.Sun));
        Say("mercury-max-elongation", me[0]); Say("mercury-max-elongation-day", me[1]);
        double[] mo = Extreme(2025, 1, 6, 20, true, e => Body(e, "Mars").Direction.Angle(e.Sun));
        Say("mars-opposition-day", mo[1]);
        Say("jupiter-opposition-mag", Body(At(2023, 11, 3, 0), "Jupiter").Magnitude);
        Say("venus-brilliancy-mag", Body(At(2025, 2, 14, 18), "Venus").Magnitude);

        Say("sun-berlin-rise", SunAlt(At(2025, 12, 21, 7 + 15.0 / 60, 52.52, 13.40)));
        Say("sun-berlin-set", SunAlt(At(2026, 6, 21, 19 + 33.0 / 60, 52.52, 13.40)));
        Say("sun-madrid-set", SunAlt(At(2025, 12, 21, 16 + 51.0 / 60, 40.42, -3.70)));
        Say("sun-sydney-rise", SunAlt(At(2025, 12, 20, 18 + 40.0 / 60, -33.87, 151.21)));
        Say("sun-quito-rise", SunAlt(At(2026, 3, 20, 11 + 18.0 / 60, -0.18, -78.47)));

        Ephemeris berlin = At(2026, 10, 29, 21, 52.52, 13.40);
        var pole = new Vec3(0, 0, 1);
        Star polaris = Star.Catalog.OrderBy(s => s.Direction.Angle(pole)).First();
        Say("polaris-alt-berlin", Math.Asin(berlin.FromJ2000.Apply(polaris.Direction).Z) * 180 / Math.PI);
        Vec3 gc = berlin.ToGalactic.Apply(berlin.FromJ2000.Apply(Vec3.FromLonLat(266.405, -28.936)));
        Say("galactic-center-l", gc.Lon); Say("galactic-center-b", gc.Lat);
        Say("stars", Star.Catalog.Length);

        EclipseSeen("eclipse-dallas-2024", 2024, 4, 8, 32.78, -96.80);
        EclipseSeen("eclipse-berlin-2028", 2028, 12, 31, 52.52, 13.40);
        EclipseSeen("eclipse-berlin-none", 2026, 10, 29, 52.52, 13.40);
    }

    /// The eclipse finder: the minute of greatest eclipse seen from a place, in
    /// hours UT, and whether it's solar (1) or lunar (0); -1 on a day without one.
    static void EclipseSeen(string name, int y, int m, int d, double lat, double lon)
    {
        Eclipse e = Eclipse.Find(y, m, d, 0, lat, lon);
        Say(name + "-ut", e == null ? -1 : e.Minute / 60.0);
        Say(name + "-solar", e == null ? -1 : e.Solar ? 1 : 0);
    }
}
