// Port of Sources/wallframes/Life.swift. Keep the two in step: the random
// draws must come in the same order.

using System;
using System.Collections.Generic;
using System.Linq;

enum Activity { Stroll, Run, Hike, Ski, Stargaze, RainWalk, Ride }
enum Animal { Deer, Bear, Fox, Hare, Hedgehog, RoofBirds, Swallows, Geese, Buzzard }

sealed class Visit
{
    public Animal Kind;
    public float At;      // along the near hill, in cabin widths from the cabin (− left)
    public float Facing;  // +1 right, −1 left
    public uint Seed;
}

/// Who's out at a frame's minute: the two who live in the cabin, now and
/// then, and wild visitors, rarely. Each day's plan is fixed by its number,
/// so all its frames tell one story; the minute, the light, the season and
/// the weather decide what of it shows.
sealed class Life
{
    public Activity? Outing;
    public float At;          // where the two are, in cabin widths from the cabin (− left)
    public float Facing = 1;
    public List<Visit> Visits = new List<Visit>();
    public uint Seed;
    public bool BikesHome { get { return Outing != Activity.Ride; } }

    public Life() { }

    /// `day` numbers the date; `starNight` says a meteor shower peaks tonight.
    public Life(int day, uint seed, int minute, SunModel sun, Season season, Sky sky, bool starNight)
    {
        Seed = Col.Hash32(unchecked((uint)day * 0x9e3779b1 ^ seed));
        var rng = new SplitMix(unchecked(((ulong)Seed * 0x9e3779b97f4a7c15) | 1));
        float alt = sun.Altitude(minute), year = season.Year;
        float? dp = sun.DayPhase(minute);
        float phase = dp.HasValue ? dp.Value : -1;
        bool snowy = season.SnowCover > 0.3f || sky == Sky.Snow, wet = sky == Sky.Rain;
        bool evening = minute > sun.Noon;
        Func<float, float, bool> within = (a, b) => phase >= a && phase <= b;
        Func<float> side = () => rng.Unit() < 0.5f ? -1 : 1;

        // The two of them: out on about one day in four, more on a meteor
        // night (they never miss one) or a rainy day (they like walking in it).
        float planRoll = rng.Unit(), kindRoll = rng.Unit(), where = rng.Unit();
        float way = side();
        Activity? plan = null;
        if (starNight) plan = Activity.Stargaze;
        else if (wet && planRoll < 0.45f) plan = Activity.RainWalk;
        else if (planRoll < 0.25f)
        {
            Activity[] kinds = snowy ? new[] { Activity.Ski, Activity.Stroll }
                                     : new[] { Activity.Hike, Activity.Stroll, Activity.Run, Activity.Ride, Activity.Stargaze };
            float[] weights = snowy ? new[] { 0.6f, 0.4f } : new[] { 0.3f, 0.3f, 0.15f, year > 0.25f && year < 0.8f ? 0.15f : 0, 0.1f };
            float k = kindRoll * weights.Aggregate(0f, (sum, w) => sum + w);
            plan = kinds[0];
            for (int i = 0; i < kinds.Length; i++)
            {
                k -= weights[i];
                if (k < 0) { plan = kinds[i]; break; }
            }
        }
        bool starry = sky != Sky.Rain && sky != Sky.Snow && sky != Sky.Fog;
        if (plan.HasValue)
        {
            switch (plan.Value)
            {
                case Activity.Stroll: if (within(0.78f, 0.98f)) { Outing = wet ? Activity.RainWalk : Activity.Stroll; At = way * (1.6f + 1.2f * where); } break;
                case Activity.Run: if (within(0.04f, 0.18f) && !snowy) { Outing = wet ? Activity.RainWalk : Activity.Run; At = way * (2.5f + 2 * where); } break;
                case Activity.Hike: if (within(0.3f, 0.7f)) { Outing = wet ? Activity.RainWalk : Activity.Hike; At = way < 0 ? -(7 + 6 * where) : 5.5f + 2 * where; } break;
                case Activity.Ski: if (within(0.3f, 0.7f)) { Outing = Activity.Ski; At = -(4 + 8 * where); } break;
                case Activity.Ride: if (within(0.3f, 0.75f) && !wet) Outing = Activity.Ride; break;
                case Activity.RainWalk: if (within(0.25f, 0.8f) && wet) { Outing = Activity.RainWalk; At = way * (1.5f + where); } break;
                case Activity.Stargaze: if (alt < -12 && (minute >= 20 * 60 + 30 || minute < 60) && starry) { Outing = Activity.Stargaze; At = way * (2 + 4 * where); } break;
            }
        }
        if (Outing == Activity.RainWalk && At == 0) At = way * (1.5f + where);
        Facing = side();

        // Visitors, each on its own days and at its own hours (at one end of
        // the day: `dusk` says which), kept apart from the two (on their far
        // side) and from each other.
        Action<Animal, float, float, float, Func<bool, bool>> visit = (animal, chance, near, far, when) =>
        {
            float roll = rng.Unit(), spot = rng.Unit(), dir = side();
            uint s = unchecked((uint)rng.Next());
            bool dusk = rng.Unit() < 0.5f;
            if (!(roll < chance) || !when(dusk) || Visits.Count >= 2) return;
            float x = dir * (near + (far - near) * spot);
            if (Outing.HasValue && Outing != Activity.Ride && (x > 0) == (At > 0) && Math.Abs(x - At) < 3) x = -x;
            if (Visits.Any(v => Math.Abs(v.At - x) < 2.5f)) x += x > 0 ? 3 : -3;
            Visits.Add(new Visit { Kind = animal, At = x, Facing = side(), Seed = s });
        };
        bool spring = year > 0.17f && year < 0.27f, autumn = year > 0.74f && year < 0.86f;
        bool warm = year > 0.35f && year < 0.83f;
        visit(Animal.Bear, 0.05f, 8, 13, _ => warm && within(0.4f, 0.92f) && !wet);           // with her cubs, far off
        visit(Animal.Deer, 0.2f, 4, 12, dusk => alt > -6 && alt < 6 && evening == dusk);       // at the wood's edge at dawn or dusk
        visit(Animal.Fox, 0.08f, 3, 10, _ => alt > -9 && alt < 1 && evening);
        visit(Animal.Hare, 0.15f, 2, 8, dusk => alt > -3 && alt < 9 && evening == dusk);
        visit(Animal.Hedgehog, 0.2f, 0.7f, 1.4f, _ => year > 0.28f && year < 0.8f && alt < -3 && alt > -13 && evening);  // under the lit window
        visit(Animal.Swallows, 0.35f, 0, 4, _ => year > 0.35f && year < 0.66f && within(0.75f, 0.95f));
        visit(Animal.RoofBirds, 0.2f, 0, 0, _ => (year < 0.2f || year > 0.9f) && within(0.1f, 0.55f));
        visit(Animal.Geese, 0.3f, 0, 0, _ => (spring || autumn) && within(0.1f, 0.55f));     // migrating
        visit(Animal.Buzzard, 0.2f, 0, 0, _ => alt > 15 && !wet);
    }

    // MARK: Drawing

    struct Pt { public float X, Y; public Pt(float x, float y) { X = x; Y = y; } }

    /// How one of the two is dressed and made.
    sealed class Look
    {
        public uint Skin, Hair, Top, Legs, Shoes;
        public bool LongHair, Glasses, Sunglasses, Coat, Shorts;
        public uint? Skirt, Scarf, Hat, Pack;
    }

    enum Pose { Walk, Run, Ski, Sit }

    /// Her: mostly green and black-and-white, shoulder-length hair, glasses,
    /// flowing skirts in spring and autumn. Him: green and orange, a comfy green
    /// hat in winter, sunglasses in summer. Backpacks when they're far from home.
    static Look[] Looks(float year, bool snowy, bool far)
    {
        bool winter = snowy || year < 0.2f || year > 0.88f, summer = year > 0.42f && year < 0.7f;
        const uint green = 0x3f8a52, black = 0x222226, white = 0xf2f2ee, orange = 0xe8792b;
        var her = new Look { Skin = 0xf0c8a6, Hair = 0x3a2a22, Top = green, Legs = black, Shoes = white, LongHair = true, Glasses = true };
        var him = new Look { Skin = 0xdcae88, Hair = 0x5a3c26, Top = orange, Legs = green, Shoes = 0x3a2e26 };
        if (winter) { her.Coat = true; her.Scarf = white; her.Shoes = black; him.Hat = 0x4f9a52; }
        else if (summer) { her.Top = white; her.Legs = green; her.Shorts = true; him.Shorts = true; him.Sunglasses = true; }
        else her.Skirt = black;
        if (far) { her.Pack = white; him.Pack = 0x2f6a3a; }
        return new[] { her, him };
    }

    static void Person(Overlay o, float x, float y, float P, float f, Pose pose, float stride, bool pointing,
                       Look look, Func<uint, RGB> lit, Pt? armTo = null)
    {
        Func<float, float, Pt> at = (dx, up) => new Pt(x + f * dx * P, y - up * P);
        Action<Pt, Pt, float, RGB> line = (a, b, w, c) => o.Line(a.X, a.Y, b.X, b.Y, w * P, c);
        Pt hip = at(0, 0.48f), shoulder = at(0.02f, 0.78f), head = at(0.04f, 0.9f);
        Pt[][] legs, arms;
        float s = stride;
        switch (pose)
        {
            case Pose.Walk:
                legs = new[] { new[] { hip, at(-0.06f * s, 0.25f), at(-0.13f * s, 0.02f) }, new[] { hip, at(0.07f * s, 0.25f), at(0.13f * s, 0.02f) } };
                arms = new[] { new[] { shoulder, at(0.07f * s, 0.63f), at(0.11f * s, 0.5f) }, new[] { shoulder, at(-0.06f * s, 0.63f), at(-0.1f * s, 0.5f) } };
                break;
            case Pose.Run:
                hip = at(0, 0.47f); shoulder = at(0.09f, 0.76f); head = at(0.13f, 0.87f);
                legs = new[] { new[] { hip, at(-0.1f, 0.3f), at(-0.24f, 0.2f) }, new[] { hip, at(0.15f, 0.3f), at(0.13f, 0.03f) } };
                arms = new[] { new[] { shoulder, at(-0.06f, 0.62f), at(0.02f, 0.55f) }, new[] { shoulder, at(0.14f, 0.64f), at(0.2f, 0.74f) } };
                break;
            case Pose.Ski:
                hip = at(-0.02f, 0.42f); shoulder = at(0.08f, 0.72f); head = at(0.12f, 0.84f);
                legs = new[] { new[] { hip, at(0.06f, 0.22f), at(-0.08f, 0.03f) }, new[] { hip, at(0.12f, 0.24f), at(0.1f, 0.03f) } };
                arms = new[] { new[] { shoulder, at(-0.02f, 0.58f), at(-0.12f, 0.48f) }, new[] { shoulder, at(0.14f, 0.6f), at(0.18f, 0.5f) } };
                break;
            default:  // sitting
                hip = at(0, 0.08f); shoulder = at(-0.08f, 0.38f); head = at(-0.09f, 0.5f);
                legs = new[] { new[] { hip, at(0.2f, 0.2f), at(0.34f, 0.03f) }, new[] { hip, at(0.22f, 0.17f), at(0.37f, 0.02f) } };
                arms = new[] { new[] { shoulder, at(-0.12f, 0.22f), at(-0.16f, 0.1f) },
                               pointing ? new[] { shoulder, at(0.04f, 0.5f), at(0.12f, 0.64f) } : new[] { shoulder, at(0.06f, 0.26f), at(0.14f, 0.2f) } };
                break;
        }
        if (armTo.HasValue)
        {
            Pt to = armTo.Value;
            arms[1] = new[] { shoulder, new Pt((shoulder.X + to.X) / 2 + f * 0.04f * P, (shoulder.Y + to.Y) / 2), to };
        }
        bool sitting = pose == Pose.Sit;

        Action<Pt[], float> leg = (j, shade) =>
        {
            RGB skin = lit(look.Skin) * shade, cloth = lit(look.Legs) * shade;
            line(j[0], j[1], 0.08f, look.Shorts ? skin : cloth);
            line(j[1], j[2], 0.075f, look.Shorts ? skin : cloth);
            if (look.Shorts) line(j[0], new Pt((j[0].X + j[1].X) / 2, (j[0].Y + j[1].Y) / 2), 0.1f, cloth);
            o.Ellipse(j[2].X + f * 0.03f * P, j[2].Y - 0.01f * P, 0.055f * P, 0.028f * P, 0, lit(look.Shoes) * shade);
        };
        Action<Pt[], float> arm = (j, shade) =>
        {
            line(j[0], j[1], 0.065f, lit(look.Top) * shade);
            line(j[1], j[2], 0.055f, (look.Shorts ? lit(look.Skin) : lit(look.Top)) * shade);  // short sleeves in summer
            o.Circle(j[2].X, j[2].Y, 0.03f * P, lit(look.Skin) * shade);
        };

        // Back to front: the far arm and leg (in shadow), the pack, the body, the near ones, the head.
        if (look.Pack.HasValue && !sitting) line(at(-0.12f, 0.74f), at(-0.13f, 0.55f), 0.17f, lit(look.Pack.Value));
        arm(arms[0], 0.8f);
        leg(legs[0], 0.8f);
        line(new Pt(hip.X, hip.Y - 0.04f * P), shoulder, 0.2f, lit(look.Top));
        if (look.Coat && !sitting)
        {
            Pt a = at(-0.09f, 0.76f), b = at(0.11f, 0.76f), c = at(0.15f, 0.3f), d = at(-0.15f, 0.3f);
            o.Polygon(new[] { a.X, a.Y, b.X, b.Y, c.X, c.Y, d.X, d.Y }, lit(look.Top));
        }
        if (look.Skirt.HasValue)
        {
            if (sitting)
            {
                Pt a = at(-0.1f, 0.18f), b = at(0.0f, 0.06f), c = at(0.28f, 0.13f), d = at(0.24f, 0.26f);
                o.Polygon(new[] { a.X, a.Y, b.X, b.Y, c.X, c.Y, d.X, d.Y }, lit(look.Skirt.Value));
            }
            else
            {
                // It flows back as she walks; a white band at its hem.
                Pt[] hem = { at(-0.22f, 0.28f), at(-0.1f, 0.26f), at(0.02f, 0.29f), at(0.14f, 0.27f) };
                Pt w0 = at(-0.09f, 0.56f), w1 = at(0.09f, 0.56f);
                var poly = new List<float> { w0.X, w0.Y, w1.X, w1.Y };
                for (int i = hem.Length - 1; i >= 0; i--) { poly.Add(hem[i].X); poly.Add(hem[i].Y); }
                o.Polygon(poly.ToArray(), lit(look.Skirt.Value));
                for (int i = 0; i + 1 < hem.Length; i++) line(hem[i], hem[i + 1], 0.03f, lit(0xf2f2ee));
            }
        }
        leg(legs[1], 1);
        if (look.Scarf.HasValue)
        {
            line(at(-0.06f, 0.8f), at(0.09f, 0.81f), 0.07f, lit(look.Scarf.Value));
            line(at(-0.04f, 0.8f), at(-0.08f, 0.64f), 0.05f, lit(look.Scarf.Value));
        }
        if (look.Pack.HasValue && !sitting) line(at(0.0f, 0.77f), at(0.05f, 0.58f), 0.025f, lit(0x222226));  // its strap
        arm(arms[1], 1);

        float hx = head.X, hy = head.Y;
        if (look.LongHair) o.Line(hx - f * 0.05f * P, hy - 0.02f * P, hx - f * 0.07f * P, hy + 0.15f * P, 0.15f * P, lit(look.Hair));
        o.Circle(hx, hy, 0.095f * P, lit(look.Skin));
        if (look.Hat.HasValue)
        {
            o.Ellipse(hx - f * 0.01f * P, hy - 0.04f * P, 0.105f * P, 0.08f * P, 0, lit(look.Hat.Value));
            o.Line(hx - f * 0.1f * P, hy - 0.005f * P, hx + f * 0.09f * P, hy - 0.005f * P, 0.045f * P, lit(look.Hat.Value) * 1.15f);  // the folded cuff
            o.Circle(hx - f * 0.02f * P, hy - 0.135f * P, 0.035f * P, lit(0xf2f2ee));
        }
        else
        {
            o.Ellipse(hx - f * 0.025f * P, hy - 0.035f * P, 0.1f * P, 0.07f * P, 0, lit(look.Hair));
        }
        if (look.Glasses)
        {
            o.Line(hx + f * 0.025f * P, hy - 0.005f * P, hx + f * 0.1f * P, hy - 0.005f * P, 0.024f * P, lit(0x1c1c1c));
            o.Line(hx + f * 0.025f * P, hy - 0.005f * P, hx - f * 0.04f * P, hy - 0.02f * P, 0.016f * P, lit(0x1c1c1c));
        }
        if (look.Sunglasses) o.Line(hx + f * 0.03f * P, hy - 0.005f * P, hx + f * 0.1f * P, hy - 0.005f * P, 0.045f * P, lit(0x141414));
    }

    /// One umbrella over the two of them, its panels every color.
    static void Umbrella(Overlay o, float cx, float rimY, float r, Func<uint, RGB> lit)
    {
        uint[] colors = { 0xd8433a, 0xf08a2c, 0xf2c94c, 0x5aa65a, 0x3f7fd0, 0x8a5ad0 };
        Func<float, float> dome = x => rimY - 0.55f * r * Col.Sqrt(Math.Max(1 - ((x - cx) / r) * ((x - cx) / r), 0));
        for (int i = 0; i < 6; i++)
        {
            float xa = cx - r + 2 * r * i / 6f, xb = cx - r + 2 * r * (i + 1) / 6f, xm = (xa + xb) / 2;
            o.Polygon(new[] { xa, rimY, xa, dome(xa), xm, dome(xm), xb, dome(xb), xb, rimY, xm, rimY - 0.07f * r }, lit(colors[i]));
        }
        o.Line(cx, rimY - 0.55f * r, cx, rimY - 0.68f * r, 0.04f * r, lit(0x222226));
    }

    static void Deer(Overlay o, float x, float y, float s, float f, bool grazing, bool antlers, bool spots, RGB coat, RGB light)
    {
        Func<float, float, Pt> at = (dx, up) => new Pt(x + f * dx * s, y - up * s);
        Action<Pt, Pt, float, RGB> line = (a, b, w, c) => o.Line(a.X, a.Y, b.X, b.Y, w * s, c);
        line(at(-0.28f, 0.52f), at(-0.3f, 0), 0.045f, coat * 0.75f);
        line(at(0.22f, 0.5f), at(0.2f, 0), 0.045f, coat * 0.75f);
        Pt body = at(0, 0.6f);
        o.Ellipse(body.X, body.Y, 0.36f * s, 0.15f * s, 0, coat);
        line(at(-0.24f, 0.52f), at(-0.22f, 0), 0.05f, coat);
        line(at(0.26f, 0.5f), at(0.28f, 0), 0.05f, coat);
        Pt rump = at(-0.35f, 0.63f);
        o.Ellipse(rump.X, rump.Y, 0.05f * s, 0.07f * s, 0, light);
        Pt head = grazing ? at(0.5f, 0.12f) : at(0.43f, 0.96f);
        line(at(0.27f, 0.66f), grazing ? at(0.46f, 0.2f) : at(0.39f, 0.9f), 0.11f, coat);
        o.Ellipse(head.X + f * 0.03f * s, head.Y + 0.01f * s, 0.1f * s, 0.055f * s, f * (grazing ? 1.1f : 0.45f), coat);
        o.Ellipse(head.X - f * 0.05f * s, head.Y - 0.06f * s, 0.025f * s, 0.05f * s, -f * 0.5f, coat);
        if (antlers)
        {
            float bx = head.X - f * 0.03f * s, by = head.Y - 0.05f * s;
            float[][] tines = { new[] { -0.1f, 0.32f }, new[] { 0.08f, 0.3f } };
            foreach (float[] t in tines)
            {
                float tipX = bx + f * t[0] * s, tipY = by - t[1] * s, midX = bx + f * t[0] * 0.5f * s, midY = by - t[1] * 0.5f * s;
                o.Line(bx, by, tipX, tipY, 0.025f * s, light * 0.8f);
                o.Line(midX, midY, midX + f * 0.09f * s, midY - 0.06f * s, 0.02f * s, light * 0.8f);
            }
        }
        if (spots)
        {
            float[][] dots = { new[] { -0.18f, 0.66f }, new[] { -0.06f, 0.68f }, new[] { 0.08f, 0.66f },
                               new[] { -0.12f, 0.58f }, new[] { 0.02f, 0.6f }, new[] { 0.15f, 0.6f } };
            foreach (float[] d in dots)
            {
                Pt p = at(d[0], d[1]);
                o.Circle(p.X, p.Y, 0.02f * s, light);
            }
        }
    }

    static void Bear(Overlay o, float x, float y, float s, float f, RGB fur, RGB muzzle)
    {
        Func<float, float, Pt> at = (dx, up) => new Pt(x + f * dx * s, y - up * s);
        Action<Pt, Pt, float, RGB> line = (a, b, w, c) => o.Line(a.X, a.Y, b.X, b.Y, w * s, c);
        line(at(-0.3f, 0.3f), at(-0.32f, 0.02f), 0.13f, fur * 0.75f);
        line(at(0.28f, 0.3f), at(0.3f, 0.02f), 0.13f, fur * 0.75f);
        Pt body = at(0, 0.42f), hump = at(0.18f, 0.55f);
        o.Ellipse(body.X, body.Y, 0.48f * s, 0.24f * s, 0, fur);
        o.Circle(hump.X, hump.Y, 0.18f * s, fur);
        line(at(-0.26f, 0.3f), at(-0.24f, 0.02f), 0.14f, fur);
        line(at(0.32f, 0.3f), at(0.36f, 0.02f), 0.14f, fur);
        Pt head = at(0.55f, 0.45f), snout = at(0.68f, 0.41f), ear1 = at(0.49f, 0.57f), ear2 = at(0.58f, 0.58f);
        o.Circle(ear1.X, ear1.Y, 0.045f * s, fur);
        o.Circle(ear2.X, ear2.Y, 0.045f * s, fur);
        o.Circle(head.X, head.Y, 0.14f * s, fur);
        o.Ellipse(snout.X, snout.Y, 0.08f * s, 0.055f * s, 0, muzzle);
        Pt nose = at(0.75f, 0.42f);
        o.Circle(nose.X, nose.Y, 0.025f * s, fur * 0.4f);
    }

    static void Fox(Overlay o, float x, float y, float s, float f, RGB fur, RGB white, RGB dark)
    {
        Func<float, float, Pt> at = (dx, up) => new Pt(x + f * dx * s, y - up * s);
        Action<Pt, Pt, float, RGB> line = (a, b, w, c) => o.Line(a.X, a.Y, b.X, b.Y, w * s, c);
        line(at(-0.15f, 0.14f), at(-0.16f, 0), 0.03f, dark);
        line(at(0.13f, 0.14f), at(0.15f, 0), 0.03f, dark);
        line(at(-0.17f, 0.17f), at(-0.35f, 0.07f), 0.08f, fur);  // the brush, white-tipped
        Pt tip = at(-0.37f, 0.06f), body = at(0, 0.18f), head = at(0.22f, 0.25f), chest = at(0.16f, 0.16f);
        o.Circle(tip.X, tip.Y, 0.035f * s, white);
        o.Ellipse(body.X, body.Y, 0.19f * s, 0.065f * s, 0, fur);
        o.Ellipse(chest.X, chest.Y, 0.05f * s, 0.04f * s, 0, white);
        o.Ellipse(head.X, head.Y, 0.06f * s, 0.045f * s, 0, fur);
        Pt n0 = at(0.25f, 0.27f), n1 = at(0.34f, 0.22f), n2 = at(0.25f, 0.2f);
        o.Polygon(new[] { n0.X, n0.Y, n1.X, n1.Y, n2.X, n2.Y }, fur);
        Pt e0 = at(0.17f, 0.27f), e1 = at(0.19f, 0.35f), e2 = at(0.23f, 0.28f);
        o.Polygon(new[] { e0.X, e0.Y, e1.X, e1.Y, e2.X, e2.Y }, fur * 0.85f);
    }

    static void Hare(Overlay o, float x, float y, float s, float f, RGB fur, RGB tail)
    {
        Func<float, float, Pt> at = (dx, up) => new Pt(x + f * dx * s, y - up * s);
        Pt body = at(0, 0.09f), head = at(0.08f, 0.18f), ear1 = at(0.05f, 0.28f), ear2 = at(0.08f, 0.28f), white = at(-0.1f, 0.08f);
        o.Ellipse(ear1.X, ear1.Y, 0.018f * s, 0.07f * s, -f * 0.35f, fur * 0.85f);
        o.Ellipse(body.X, body.Y, 0.1f * s, 0.085f * s, 0, fur);
        o.Circle(head.X, head.Y, 0.05f * s, fur);
        o.Ellipse(ear2.X, ear2.Y, 0.018f * s, 0.07f * s, -f * 0.15f, fur);
        o.Circle(white.X, white.Y, 0.025f * s, tail);
    }

    static void Hedgehog(Overlay o, float x, float y, float s, float f, RGB spines, RGB face)
    {
        float bx = x, by = y - 0.045f * s;
        o.Ellipse(bx, by, 0.09f * s, 0.05f * s, 0, spines);
        for (int k = 0; k < 5; k++)
        {
            float a = (float)Math.PI * (0.15f + 0.7f * k / 4);
            o.Circle(bx - (float)Math.Cos(a) * 0.07f * s, by - (float)Math.Sin(a) * 0.035f * s, 0.009f * s, spines * 1.5f);
        }
        o.Ellipse(x + f * 0.085f * s, y - 0.025f * s, 0.035f * s, 0.022f * s, 0, face);
        o.Circle(x + f * 0.12f * s, y - 0.025f * s, 0.009f * s, spines * 0.3f);
    }

    /// A bird on the wing, seen from the side or below: two wings bent at the
    /// wrist, `flap` lifting their tips.
    static void FlyingBird(Overlay o, float x, float y, float span, float flap, float broad, RGB color)
    {
        float tip = span / 2, wrist = 0.22f * span;
        float[] pts = { x - tip, y - flap * 0.3f * span, x - wrist, y - 0.04f * span, x, y + 0.03f * span,
                        x + wrist, y - 0.04f * span, x + tip, y - flap * 0.3f * span };
        for (int i = 0; i + 3 < pts.Length; i += 2) o.Line(pts[i], pts[i + 1], pts[i + 2], pts[i + 3], broad * span, color);
        o.Ellipse(x, y + 0.03f * span, 0.06f * span, 0.04f * span, 0, color);
    }

    /// Paints the two and their visitors onto the near hill's patch. `ground`
    /// gives the hill's top at x; `clearing` the nearest x near another where
    /// no tree stands on the ridge, for a figure that should show against the
    /// sky, or NaN when there's none near.
    public void Draw(Overlay o, Cabin cabin, float H, float width, float year, bool snowy,
                     Func<float, float> ground, Func<float, float, float> clearing, Func<uint, RGB> lit, float lamp)
    {
        float P = 0.7f * cabin.WallH, unit = 2 * cabin.HalfWidth;
        Func<float, float> place = a => Math.Min(Math.Max(cabin.X + a * unit, 0.04f * width), 0.96f * width);
        var rng = new SplitMix(unchecked(((ulong)Seed * 0x2545f4914f6cdd1d) | 1));

        foreach (Visit v in Visits)
        {
            var r = new SplitMix((ulong)v.Seed | 1);
            float x = place(v.At), f = v.Facing;
            switch (v.Kind)
            {
                case Animal.Deer:
                {
                    // A doe or two; a spotted fawn in early summer; a stag with antlers from August to March.
                    float y = ground(x) + 0.012f * H;
                    RGB coat = lit(year > 0.3f && year < 0.75f ? 0x9a5c38u : 0x6f5c4cu), light = lit(0xe8dcc8);
                    bool stag = (year > 0.6f || year < 0.2f) && r.Unit() < 0.4f;
                    Deer(o, x, y, P * (stag ? 1.1f : 1), f, r.Unit() < 0.5f, stag, false, coat, light);
                    if (year > 0.4f && year < 0.62f)
                        Deer(o, x - f * 0.55f * P, y + 0.004f * H, 0.62f * P, f, false, false, true, coat, light);
                    else if (!stag && r.Unit() < 0.6f)
                        Deer(o, x + f * 0.75f * P, y + 0.003f * H, 0.95f * P, -f, true, false, false, coat, light);
                    break;
                }
                case Animal.Bear:
                {
                    float y = ground(x) + 0.01f * H;
                    RGB fur = lit(0x4b3426), muzzle = lit(0x8a6a4a);
                    Bear(o, x, y, P, f, fur, muzzle);
                    Bear(o, x - f * 0.85f * P, y + 0.002f * H, 0.42f * P, f, fur, muzzle);
                    Bear(o, x - f * 1.25f * P, y - 0.001f * H, 0.4f * P, f, fur, muzzle);
                    break;
                }
                case Animal.Fox:
                    Fox(o, x, ground(x) + 0.01f * H, P, f, lit(0xc8642a), lit(0xf0ece4), lit(0x2a1e18));
                    break;
                case Animal.Hare:
                    // White in winter, as the mountain hare turns.
                    Hare(o, x, ground(x) + 0.014f * H, P, f, lit(snowy ? 0xeef0f2u : 0x8e7454u), lit(0xf4f4f0));
                    break;
                case Animal.Hedgehog:
                {
                    float y = cabin.Base + 0.008f * H;
                    RGB warm = lit(0x6a5444) + RGB.Hex(0xffb35c) * (0.12f * lamp);
                    Hedgehog(o, x, y, P, f, warm, lit(0xc8a882) + RGB.Hex(0xffb35c) * (0.12f * lamp));
                    if (year > 0.55f)  // her hoglets, in late summer
                        for (int k = 1; k <= 3; k++) Hedgehog(o, x - f * (0.14f + 0.12f * k) * P, y + 0.002f * H * (k % 2), 0.55f * P, f, warm, warm * 1.4f);
                    break;
                }
                case Animal.RoofBirds:
                {
                    // Tits and a robin on the roof's ridge and slope.
                    float apexY = cabin.Base - cabin.WallH - cabin.RoofH;
                    for (int k = 0; k < 3; k++)
                    {
                        float t = 0.1f + 0.25f * k + 0.05f * r.Unit(), s = k % 2 == 0 ? 1 : -1;
                        float bx = cabin.X + s * t * 1.08f * cabin.HalfWidth, by = apexY + t * cabin.RoofH - 0.03f * P;
                        RGB body = lit(k == 1 ? 0xd8703au : 0xe0c040u);
                        o.Circle(bx, by, 0.045f * P, body);
                        o.Circle(bx + s * 0.04f * P, by - 0.035f * P, 0.03f * P, lit(k == 1 ? 0x6a5444u : 0x1c1c22u));
                        o.Line(bx - s * 0.04f * P, by, bx - s * 0.1f * P, by + 0.02f * P, 0.025f * P, lit(0x4a5a6a));
                    }
                    break;
                }
                case Animal.Swallows:
                    // Swallows hawking for insects over the treetops in the evening.
                    for (int k = 0; k < 7; k++)
                    {
                        float bx = x + (r.Unit() - 0.5f) * 8 * P, by = ground(x) - (3 + 2.5f * r.Unit()) * P;
                        FlyingBird(o, bx, by, 0.32f * P, 0.6f * r.Unit() - 0.3f, 0.1f, lit(0x1e2430));
                    }
                    break;
            }
        }

        if (!Outing.HasValue || Outing == Activity.Ride) return;
        Activity outing = Outing.Value;
        bool far = Math.Abs(At) > 5;
        Look[] looks = Looks(year, snowy, far);
        Look her = looks[0], him = looks[1];
        float fc = Facing, s0 = 2 * rng.Unit() - 1;
        switch (outing)
        {
            case Activity.Stroll:
            case Activity.RainWalk:
            case Activity.Hike:
            {
                // Side by side, walking; on a hike along the ridge if there's a gap in the trees, with packs.
                float gap = outing == Activity.Hike ? clearing(place(At), 0.6f * P) : float.NaN;
                float x = float.IsNaN(gap) ? place(At) : gap;
                float y = float.IsNaN(gap) ? ground(x) + 0.008f * H : ground(x) + 0.002f * H;
                if (outing == Activity.RainWalk)
                {
                    // Close together under his umbrella.
                    float rimY = y - 1.05f * P;
                    var hand = new Pt(x, y - 0.7f * P);
                    Person(o, x - fc * 0.14f * P, y - 0.002f * H, P, fc, Pose.Walk, s0, false, her, lit);
                    Person(o, x + fc * 0.14f * P, y, P * 1.05f, fc, Pose.Walk, -s0, false, him, lit, hand);
                    o.Line(x, rimY - 0.2f * P, x, hand.Y, 0.025f * P, lit(0x222226));
                    Umbrella(o, x, rimY, 0.44f * P, lit);
                }
                else
                {
                    Person(o, x - fc * 0.22f * P, y - 0.002f * H, P, fc, Pose.Walk, s0, false, her, lit);
                    Person(o, x + fc * 0.22f * P, y, P * 1.05f, fc, Pose.Walk, -s0, false, him, lit);
                }
                break;
            }
            case Activity.Run:
            {
                float x = place(At), y = ground(x) + 0.01f * H;
                Person(o, x - fc * 0.5f * P, y - 0.002f * H, P, fc, Pose.Run, 0, false, her, lit);
                Person(o, x + fc * 0.3f * P, y, P * 1.05f, fc, Pose.Run, 0, false, him, lit);
                break;
            }
            case Activity.Ski:
            {
                // Cross-country, one behind the other, on her green skis and his orange ones.
                float x = place(At), y = ground(x) + 0.02f * H;
                float[] dxs = { -0.7f, 0.5f }, scales = { 1, 1.05f };
                uint[] skis = { 0x3f8a52, 0xe8792b };
                Look[] who = { her, him };
                for (int k = 0; k < 2; k++)
                {
                    float px = x + fc * dxs[k] * P, sP = P * scales[k];
                    o.Line(px - fc * 0.5f * sP, y, px + fc * 0.55f * sP, y, 0.035f * sP, lit(skis[k]));
                    o.Line(px + fc * 0.55f * sP, y, px + fc * 0.63f * sP, y - 0.05f * sP, 0.035f * sP, lit(skis[k]));
                    Person(o, px, y - 0.02f * sP, sP, fc, Pose.Ski, 0, false, who[k], lit);
                    o.Line(px - fc * 0.12f * sP, y - 0.5f * sP, px - fc * 0.32f * sP, y, 0.02f * sP, lit(0x3a3a3a));
                    o.Line(px + fc * 0.18f * sP, y - 0.52f * sP, px + fc * 0.02f * sP, y, 0.02f * sP, lit(0x3a3a3a));
                }
                break;
            }
            case Activity.Stargaze:
            {
                // On a blanket on the ridge, against the stars: she points, his
                // red headlamp keeps their eyes dark-adapted, the telescope looks up.
                float gap = clearing(place(At), 1.2f * P);
                float x = float.IsNaN(gap) ? place(At) : gap, y = ground(x) + (float.IsNaN(gap) ? 0.01f : 0.002f) * H;
                o.Ellipse(x + fc * 0.1f * P, y - 0.015f * P, 0.65f * P, 0.05f * P, 0, lit(0x8a3a3a));
                Person(o, x - fc * 0.3f * P, y, P, fc, Pose.Sit, 0, true, her, lit);
                Person(o, x + fc * 0.15f * P, y, P * 1.05f, fc, Pose.Sit, 0, false, him, lit);
                float tx = x + fc * 0.85f * P;
                foreach (float dx in new[] { -0.13f, 0.02f, 0.14f }) o.Line(tx, y - 0.42f * P, tx + fc * dx * P, y, 0.02f * P, lit(0x3a3a3a));
                o.Line(tx - fc * 0.12f * P, y - 0.36f * P, tx + fc * 0.14f * P, y - 0.64f * P, 0.07f * P, lit(0xd8d8d0));
                float lampX = x + fc * (0.15f - 0.09f * 1.05f) * P, lampY = y - 0.5f * 1.05f * P;
                o.Glow(lampX, lampY, 0.025f * P, new RGB(0.6f, 0.04f, 0.01f));
                o.Glow(lampX, lampY, 0.12f * P, new RGB(0.04f, 0.003f, 0.001f));
                break;
            }
        }
    }

    /// The birds in the sky: a skein of geese in a V on their way, or a
    /// buzzard circling on a thermal. They fly behind the hills.
    public Overlay DrawSky(float width, float H, RGB color)
    {
        foreach (Visit v in Visits)
        {
            if (v.Kind != Animal.Geese && v.Kind != Animal.Buzzard) continue;
            var r = new SplitMix((ulong)v.Seed | 1);
            float x = (0.15f + 0.7f * r.Unit()) * width, y = (0.22f + 0.2f * r.Unit()) * H;
            if (v.Kind == Animal.Buzzard)
            {
                float span = 0.016f * H;
                var b = new Overlay((int)(x - span), (int)(y - span), (int)(x + span) + 1, (int)(y + span) + 1);
                FlyingBird(b, x, y, span, -0.1f, 0.16f, color);
                b.Ellipse(x, y + 0.08f * span, 0.06f * span, 0.12f * span, 0, color);  // its fanned tail
                return b;
            }
            int n = 7 + (int)(r.Unit() * 8);
            float gap = 0.009f * H, span2 = 0.0065f * H, f = v.Facing;
            float reach = (n / 2 + 1) * gap;
            var o = new Overlay((int)(x - 1.2f * reach - span2), (int)(y - 0.6f * reach - span2),
                                (int)(x + 1.2f * reach + span2) + 1, (int)(y + 0.6f * reach + span2) + 1);
            for (int i = 0; i < n; i++)
            {
                float rank = (i + 1) / 2, arm = i % 2 == 0 ? 1 : -1;
                float bx = x + f * (0.5f * reach - rank * gap), by = y + arm * rank * gap * 0.42f + (r.Unit() - 0.5f) * 0.15f * gap;
                FlyingBird(o, bx, by, span2 * (0.9f + 0.2f * r.Unit()), 1.2f * r.Unit() - 0.4f, 0.13f, color);
            }
            return o;
        }
        return null;
    }
}
