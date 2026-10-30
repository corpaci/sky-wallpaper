// Port of Sources/wallframes/Astronomy.swift, in C# 5. Keep the two in step:
// tests/astronomy.sh checks both against known events and against each other.
//
// Where the sun, moon, planets and stars stand, for one place and moment.
// Sun, moon and planets follow Paul Schlyter's "How to compute planetary
// positions" (stjarnhimlen.se/comp/ppcomp.html): an arcminute or two for the
// sun and moon, a few for the planets, well under a pixel here. Directions
// are unit vectors in the observer's frame: x east, y north, z up.

using System;
using System.Collections.Generic;
using System.Globalization;

struct Vec3
{
    public double X, Y, Z;

    public Vec3(double x, double y, double z) { X = x; Y = y; Z = z; }

    /// From longitude (or right ascension) and latitude (or declination), degrees.
    public static Vec3 FromLonLat(double lon, double lat)
    {
        return new Vec3(Math.Cos(lat * Astro.Rad) * Math.Cos(lon * Astro.Rad),
                        Math.Cos(lat * Astro.Rad) * Math.Sin(lon * Astro.Rad), Math.Sin(lat * Astro.Rad));
    }

    public static Vec3 operator +(Vec3 a, Vec3 b) { return new Vec3(a.X + b.X, a.Y + b.Y, a.Z + b.Z); }
    public static Vec3 operator -(Vec3 a, Vec3 b) { return new Vec3(a.X - b.X, a.Y - b.Y, a.Z - b.Z); }
    public static Vec3 operator *(Vec3 a, double k) { return new Vec3(a.X * k, a.Y * k, a.Z * k); }
    public double Dot(Vec3 b) { return X * b.X + Y * b.Y + Z * b.Z; }
    public Vec3 Cross(Vec3 b) { return new Vec3(Y * b.Z - Z * b.Y, Z * b.X - X * b.Z, X * b.Y - Y * b.X); }
    public double Length { get { return Math.Sqrt(Dot(this)); } }
    public Vec3 Unit { get { return this * (1 / Length); } }
    /// Angle to another direction in degrees, exact for small angles too.
    public double Angle(Vec3 b) { return Math.Atan2(Cross(b).Length, Dot(b)) / Astro.Rad; }
    public double Lon { get { return Math.Atan2(Y, X) / Astro.Rad; } }
    public double Lat { get { return Math.Atan2(Z, Math.Sqrt(X * X + Y * Y)) / Astro.Rad; } }
}

/// A rotation, as three rows.
struct Mat3
{
    public Vec3 R0, R1, R2;

    public Mat3(Vec3 r0, Vec3 r1, Vec3 r2) { R0 = r0; R1 = r1; R2 = r2; }

    public Vec3 Apply(Vec3 v) { return new Vec3(R0.Dot(v), R1.Dot(v), R2.Dot(v)); }

    public Mat3 Transposed
    {
        get { return new Mat3(new Vec3(R0.X, R1.X, R2.X), new Vec3(R0.Y, R1.Y, R2.Y), new Vec3(R0.Z, R1.Z, R2.Z)); }
    }

    public static Mat3 operator *(Mat3 m, Mat3 n)
    {
        Mat3 t = n.Transposed;
        return new Mat3(t.Apply(m.R0), t.Apply(m.R1), t.Apply(m.R2));
    }

    /// Turns vectors by `deg` about the x or z axis.
    public static Mat3 RotX(double deg)
    {
        double c = Math.Cos(deg * Astro.Rad), s = Math.Sin(deg * Astro.Rad);
        return new Mat3(new Vec3(1, 0, 0), new Vec3(0, c, -s), new Vec3(0, s, c));
    }

    public static Mat3 RotZ(double deg)
    {
        double c = Math.Cos(deg * Astro.Rad), s = Math.Sin(deg * Astro.Rad);
        return new Mat3(new Vec3(c, -s, 0), new Vec3(s, c, 0), new Vec3(0, 0, 1));
    }
}

static class Astro
{
    public const double Rad = Math.PI / 180;

    /// Equatorial J2000 → galactic (IAU, as in the Hipparcos catalogue).
    public static readonly Mat3 Galactic = new Mat3(new Vec3(-0.0548755604, -0.8734370902, -0.4838350155),
                                                    new Vec3(0.4941094279, -0.4448296300, 0.7469822445),
                                                    new Vec3(-0.8676661490, -0.1980763734, 0.4559837762));
}

/// Elements of an orbit, of date: node N, inclination I, argument of
/// perihelion W and mean anomaly M in degrees; semi-major axis A;
/// eccentricity E.
struct Orbit
{
    public double N, I, W, A, E, M;

    public Orbit(double n, double i, double w, double a, double e, double m) { N = n; I = i; W = w; A = a; E = e; M = m; }

    /// Position in the ecliptic frame, in units of `A`.
    public Vec3 Position()
    {
        double m = M * Astro.Rad;
        double ea = m + E * Math.Sin(m) * (1 + E * Math.Cos(m));
        for (int k = 0; k < 5; k++) ea -= (ea - E * Math.Sin(ea) - m) / (1 - E * Math.Cos(ea));
        double xv = A * (Math.Cos(ea) - E), yv = A * Math.Sqrt(1 - E * E) * Math.Sin(ea);
        double r = Math.Sqrt(xv * xv + yv * yv), vw = Math.Atan2(yv, xv) + W * Astro.Rad;
        double n = N * Astro.Rad, inc = I * Astro.Rad;
        return new Vec3(r * (Math.Cos(n) * Math.Cos(vw) - Math.Sin(n) * Math.Sin(vw) * Math.Cos(inc)),
                        r * (Math.Sin(n) * Math.Cos(vw) + Math.Cos(n) * Math.Sin(vw) * Math.Cos(inc)),
                        r * Math.Sin(vw) * Math.Sin(inc));
    }
}

sealed class Planet
{
    public string Name;
    public Vec3 Direction;   // horizontal
    public double Magnitude;
    public double Bv;        // color index, as for stars
}

/// The sky for one place and moment.
sealed class Ephemeris
{
    public readonly double Latitude;
    public readonly Mat3 FromJ2000;        // equatorial J2000 → horizontal
    public readonly Mat3 ToGalactic;       // horizontal → galactic
    public readonly Mat3 ToEcliptic;       // horizontal → ecliptic of date
    public readonly Vec3 Sun;              // horizontal directions
    public readonly Vec3 Moon;             // as seen from here: parallax shifts it up to 1°
    public readonly Vec3 MoonFromCenter;   // as seen from the Earth's center, for eclipse geometry
    public readonly double MoonRadius;     // apparent, degrees, from here
    public readonly double SunRadius;      // apparent, degrees
    public readonly double SunLongitude;   // ecliptic, degrees
    public readonly double MoonPhaseAngle; // sun–moon–observer, degrees: 0 full, 180 new
    public readonly Vec3 EclipticPole;     // horizontal; the moon's axis stays within 1.5° of it
    public readonly List<Planet> Planets = new List<Planet>();

    /// Schlyter's day number: days since 2000 Jan 0.0 UT.
    public static double DayNumber(int year, int month, int day, double minutesUT)
    {
        // Days from the civil calendar (Howard Hinnant's algorithm), from 1970-01-01.
        int y = month <= 2 ? year - 1 : year;
        int era = (y >= 0 ? y : y - 399) / 400;
        int yoe = y - era * 400;
        int doy = (153 * ((month + 9) % 12) + 2) / 5 + day - 1;
        int days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468;
        return (days - 10956) + minutesUT / 1440;
    }

    static double S(double deg) { return Math.Sin(deg * Astro.Rad); }

    public Ephemeris(double latitude, double longitude, double d)
    {
        Latitude = latitude;
        double ecl = 23.4393 - 3.563e-7 * d;
        Mat3 toEquator = Mat3.RotX(ecl);

        var sunOrbit = new Orbit(0, 0, 282.9404 + 4.70935e-5 * d, 1, 0.016709 - 1.151e-9 * d, 356.0470 + 0.9856002585 * d);
        Vec3 sunEcl = sunOrbit.Position();  // geocentric, AU

        // The moon, with the largest perturbations by the sun.
        var mo = new Orbit(125.1228 - 0.0529538083 * d, 5.1454, 318.0634 + 0.1643573223 * d,
                           60.2666, 0.054900, 115.3654 + 13.0649929509 * d);
        Vec3 raw = mo.Position();
        double Ms = sunOrbit.M, Mm = mo.M;
        double D = Mm + mo.W + mo.N - Ms - sunOrbit.W, F = Mm + mo.W;
        double dLon = -1.274 * S(Mm - 2 * D) + 0.658 * S(2 * D) - 0.186 * S(Ms) - 0.059 * S(2 * Mm - 2 * D)
            - 0.057 * S(Mm - 2 * D + Ms) + 0.053 * S(Mm + 2 * D) + 0.046 * S(2 * D - Ms) + 0.041 * S(Mm - Ms)
            - 0.035 * S(D) - 0.031 * S(Mm + Ms) - 0.015 * S(2 * F - 2 * D) + 0.011 * S(Mm - 4 * D);
        double dLat = -0.173 * S(F - 2 * D) - 0.055 * S(Mm - F - 2 * D) - 0.046 * S(Mm + F - 2 * D)
            + 0.033 * S(F + 2 * D) + 0.017 * S(2 * Mm + F);
        double dist = raw.Length - 0.58 * Math.Cos((Mm - 2 * D) * Astro.Rad) - 0.46 * Math.Cos(2 * D * Astro.Rad);
        Vec3 moonEcl = Vec3.FromLonLat(raw.Lon + dLon, raw.Lat + dLat) * dist;  // Earth radii

        // Sidereal time, then equatorial of date → horizontal.
        double lst = 280.46061837 + 360.98564736629 * (d - 1.5) + longitude;
        double ct = Math.Cos(lst * Astro.Rad), st = Math.Sin(lst * Astro.Rad);
        double cp = Math.Cos(latitude * Astro.Rad), sp = Math.Sin(latitude * Astro.Rad);
        var toHorizon = new Mat3(new Vec3(-st, ct, 0), new Vec3(-sp * ct, -sp * st, cp), new Vec3(cp * ct, cp * st, sp));
        Mat3 fromEcliptic = toHorizon * toEquator;
        // Precession since J2000, as a turn about the ecliptic pole.
        Mat3 precess = toEquator * Mat3.RotZ(3.82394e-5 * d) * Mat3.RotX(-ecl);

        FromJ2000 = toHorizon * precess;
        ToGalactic = Astro.Galactic * precess.Transposed * toHorizon.Transposed;
        ToEcliptic = fromEcliptic.Transposed;
        Sun = fromEcliptic.Apply(sunEcl).Unit;
        MoonFromCenter = fromEcliptic.Apply(moonEcl).Unit;
        Vec3 fromHere = fromEcliptic.Apply(moonEcl) - new Vec3(0, 0, 1);  // the observer stands one Earth radius up
        Moon = fromHere.Unit;
        MoonRadius = Math.Asin(0.2725 / fromHere.Length) / Astro.Rad;
        SunRadius = 0.2666 / sunEcl.Length;
        SunLongitude = sunEcl.Lon;
        const double earthRadiiPerAU = 23454.8;
        MoonPhaseAngle = (sunEcl * earthRadiiPerAU - moonEcl).Angle(moonEcl * -1);
        EclipticPole = fromEcliptic.Apply(new Vec3(0, 0, 1));

        // Planets: heliocentric orbits, Jupiter and Saturn perturbing each other.
        double mj = 19.8950 + 0.0830853001 * d, ms = 316.9670 + 0.0334442282 * d;
        string[] names = { "Mercury", "Venus", "Mars", "Jupiter", "Saturn" };
        Orbit[] orbits = {
            new Orbit(48.3313 + 3.24587e-5 * d, 7.0047 + 5.00e-8 * d, 29.1241 + 1.01444e-5 * d,
                      0.387098, 0.205635 + 5.59e-10 * d, 168.6562 + 4.0923344368 * d),
            new Orbit(76.6799 + 2.46590e-5 * d, 3.3946 + 2.75e-8 * d, 54.8910 + 1.38374e-5 * d,
                      0.723330, 0.006773 - 1.302e-9 * d, 48.0052 + 1.6021302244 * d),
            new Orbit(49.5574 + 2.11081e-5 * d, 1.8497 - 1.78e-8 * d, 286.5016 + 2.92961e-5 * d,
                      1.523688, 0.093405 + 2.516e-9 * d, 18.6021 + 0.5240207766 * d),
            new Orbit(100.4542 + 2.76854e-5 * d, 1.3030 - 1.557e-7 * d, 273.8777 + 1.64505e-5 * d,
                      5.20256, 0.048498 + 4.469e-9 * d, mj),
            new Orbit(113.6634 + 2.38980e-5 * d, 2.4886 - 1.081e-7 * d, 339.3939 + 2.97661e-5 * d,
                      9.55475, 0.055546 - 9.499e-9 * d, ms),
        };
        double[] bvs = { 0.93, 0.82, 1.36, 0.83, 1.04 };
        for (int k = 0; k < names.Length; k++)
        {
            Vec3 helio = orbits[k].Position();
            if (names[k] == "Jupiter")
            {
                double dl = -0.332 * S(2 * mj - 5 * ms - 67.6) - 0.056 * S(2 * mj - 2 * ms + 21) + 0.042 * S(3 * mj - 5 * ms + 21)
                    - 0.036 * S(mj - 2 * ms) + 0.022 * Math.Cos((mj - ms) * Astro.Rad) + 0.023 * S(2 * mj - 3 * ms + 52)
                    - 0.016 * S(mj - 5 * ms - 69);
                helio = Vec3.FromLonLat(helio.Lon + dl, helio.Lat) * helio.Length;
            }
            else if (names[k] == "Saturn")
            {
                double dl = 0.812 * S(2 * mj - 5 * ms - 67.6) - 0.229 * Math.Cos((2 * mj - 4 * ms - 2) * Astro.Rad)
                    + 0.119 * S(mj - 2 * ms - 3) + 0.046 * S(2 * mj - 6 * ms - 69) + 0.014 * S(mj - 3 * ms + 32);
                double db = -0.020 * Math.Cos((2 * mj - 4 * ms - 2) * Astro.Rad) + 0.018 * S(2 * mj - 6 * ms - 49);
                helio = Vec3.FromLonLat(helio.Lon + dl, helio.Lat + db) * helio.Length;
            }
            Vec3 geo = helio + sunEcl;
            double r = helio.Length, R = geo.Length, sd = sunEcl.Length;
            double fv = Math.Acos(Math.Max(-1, Math.Min(1, (r * r + R * R - sd * sd) / (2 * r * R)))) / Astro.Rad;  // phase angle
            double baseMag = 5 * Math.Log10(r * R);
            double mag;
            switch (names[k])
            {
                case "Mercury": mag = -0.36 + baseMag + 0.027 * fv + 2.2e-13 * Math.Pow(fv, 6); break;
                case "Venus": mag = -4.34 + baseMag + 0.013 * fv + 4.2e-7 * Math.Pow(fv, 3); break;
                case "Mars": mag = -1.51 + baseMag + 0.016 * fv; break;
                case "Jupiter": mag = -9.25 + baseMag + 0.014 * fv; break;
                default: mag = -9.0 + baseMag + 0.044 * fv; break;  // Saturn, rings left out
            }
            Planets.Add(new Planet { Name = names[k], Direction = fromEcliptic.Apply(geo).Unit, Magnitude = mag, Bv = bvs[k] });
        }
    }

    /// Illuminated fraction of the moon's disk.
    public double MoonLit { get { return (1 + Math.Cos(MoonPhaseAngle * Astro.Rad)) / 2; } }
}

/// The Yale Bright Star Catalogue down to magnitude 5.5 (`Stars.cs`).
sealed class Star
{
    public Vec3 Direction;  // equatorial J2000
    public float Magnitude, Bv;

    public static readonly Star[] Catalog = ReadCatalog();

    static Star[] ReadCatalog()
    {
        var stars = new List<Star>();
        foreach (string line in StarData.Text.Split('\n'))
        {
            string[] f = line.Trim().Split(' ');
            if (f.Length < 4) continue;
            Func<int, double> num = i => double.Parse(f[i], CultureInfo.InvariantCulture);
            stars.Add(new Star { Direction = Vec3.FromLonLat(num(0), num(1)), Magnitude = (float)num(2), Bv = (float)num(3) });
        }
        return stars.ToArray();
    }

    /// The Milky Way's grain: 90,000 points too faint to see one by one,
    /// most near the great star clouds, the rest along the band, as bright as
    /// `MilkyWay` is where they fall (so dust dims them). `Light` is 0…1.5.
    public sealed class Grain
    {
        public Vec3 Direction;
        public float Light, Bv;
    }

    public static readonly Grain[] Grains = MakeGrain();

    static Grain[] MakeGrain()
    {
        var rng = new SplitMix(0x6d2b79f5a1b2c3d4);
        Mat3 toJ2000 = Astro.Galactic.Transposed;
        var grain = new Grain[90000];
        float pi = (float)Math.PI;
        for (int n = 0; n < grain.Length; n++)
        {
            float pick = rng.Unit(), u = 2 * rng.Unit() - 1;
            float l = pick < 0.3f ? 14 * u : pick < 0.42f ? 30 + 12 * u : pick < 0.54f ? 77 + 14 * u
                : pick < 0.62f ? -60 + 18 * u : 180 * u;
            float u1 = Math.Max(rng.Unit(), 1e-6f), u2 = rng.Unit();
            float normal = Col.Sqrt(-2 * (float)Math.Log(u1)) * (float)Math.Cos(2 * pi * u2);  // Box–Muller
            float b = normal * (2.5f + 4.5f * (0.5f + 0.5f * (float)Math.Cos(l * pi / 180)));
            float light = (0.25f + 0.75f * Col.Pow(rng.Unit(), 4)) * Math.Min(Col.Pow(NightSky.MilkyWay(l, b)[0], 1.3f), 3) / 2;
            grain[n] = new Grain { Direction = toJ2000.Apply(Vec3.FromLonLat(l, b)), Light = light, Bv = 1.4f * rng.Unit() };
        }
        return grain;
    }
}

/// The day's eclipse, if one is seen from here: a solar one with the sun
/// up, or a lunar one with the moon up and in the Earth's umbra (the
/// penumbra alone barely shows) while the sun is down. Its local minute of
/// greatest phase as seen from here, found to the minute.
sealed class Eclipse
{
    public int Minute;
    public bool Solar;

    public static Eclipse Find(int year, int month, int day, int utcOffset, double latitude, double longitude)
    {
        Func<int, double[]> depth = minute =>  // > 0 when eclipsed and seen: solar, lunar
        {
            var sky = new Ephemeris(latitude, longitude, Ephemeris.DayNumber(year, month, day, minute - utcOffset));
            double solar = sky.Sun.Z > 0 ? sky.SunRadius + sky.MoonRadius - sky.Moon.Angle(sky.Sun) : -1;
            double lunar = sky.Moon.Z > 0 && sky.Sun.Z < 0 ? 0.70 + 0.26 - sky.MoonFromCenter.Angle(sky.Sun * -1) : -1;
            return new[] { solar, lunar };
        };
        Eclipse best = null;
        double bestDepth = 0;
        for (int coarse = 0; coarse < 1440; coarse += 10)
        {
            double[] d = depth(coarse);
            if (!(Math.Max(d[0], d[1]) > -0.3)) continue;  // near enough to look closer
            for (int minute = Math.Max(coarse - 10, 0); minute <= Math.Min(coarse + 10, 1439); minute++)
            {
                double[] m = depth(minute);
                for (int k = 0; k < 2; k++)
                {
                    if (m[k] > 0 && m[k] > bestDepth) { best = new Eclipse { Minute = minute, Solar = k == 0 }; bestDepth = m[k]; }
                }
            }
        }
        return best;
    }
}
