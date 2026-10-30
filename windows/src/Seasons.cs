// Port of Sources/wallframes/Seasons.swift. Keep the two in step.

using System;

/// The time of year and the state of the ground, for one frame. Without a
/// forecast it follows the date alone: the summit's snow line rises and
/// falls with the year, and no snow or frost is invented. With one, the
/// snow line follows the day's freezing level, and snow and frost lie only
/// where the forecast has them.
struct Season
{
    public float Year;       // 0…1 through the local year: from Jan 1 north of the equator, Jul 1 south of it
    public float SnowLine;   // on the summit: 0 at its foot … 1 at its top
    public float SnowCover;  // snow lying on the land, 0…1
    public float Frost;      // hoarfrost on the meadow, 0…1
    public bool Warm;        // a warm evening, for fireflies

    public Season(float year)
    {
        Year = year;
        SnowLine = 0.49f + 0.39f * (float)Math.Cos(2 * (float)Math.PI * (year - 0.58f));  // highest at the end of July, a cap left
        SnowCover = 0;
        Frost = 0;
        Warm = true;
    }

    /// For a date and the hemisphere.
    public static Season ForDate(int y, int month, int day, double latitude)
    {
        double start = Ephemeris.DayNumber(y, 1, 1, 0);
        double length = Ephemeris.DayNumber(y + 1, 1, 1, 0) - start;
        float north = (float)((Ephemeris.DayNumber(y, month, day, 720) - start) / length);
        return new Season(latitude >= 0 ? north : (north + 0.5f) % 1);
    }

    // Leafy trees: leaves out from early April, fresh green into May,
    // turning orange, yellow, red and brown from late September, fallen by
    // late November.
    public float LeafFill { get { return Col.Smoothstep(0.26f, 0.36f, Year) * (1 - Col.Smoothstep(0.84f, 0.91f, Year)); } }
    public float LeafFresh { get { return Bump(Year, 0.26f, 0.30f, 0.40f, 0.48f); } }
    public float LeafAutumn { get { return Bump(Year, 0.70f, 0.76f, 0.86f, 0.92f); } }
    // Fruit trees: in blossom from mid-April to mid-May, apples from August to mid-October.
    public float Blossom { get { return Bump(Year, 0.28f, 0.31f, 0.36f, 0.39f); } }
    public float Fruit { get { return Bump(Year, 0.60f, 0.66f, 0.75f, 0.80f); } }

    /// How much of the meadow is in flower, 0…1: crocuses, then the spring
    /// meadow, then summer's, then heather.
    public float Flowers
    {
        get
        {
            return 0.5f * Bump(Year, 0.22f, 0.26f, 0.31f, 0.35f) + Bump(Year, 0.32f, 0.36f, 0.45f, 0.50f)
                + 0.7f * Bump(Year, 0.46f, 0.50f, 0.60f, 0.65f) + 0.35f * Bump(Year, 0.62f, 0.66f, 0.70f, 0.75f);
        }
    }

    /// The flower colors in bloom now; a flower picks one by its own number.
    public uint[] FlowerColors
    {
        get
        {
            return Year < 0.32f ? new uint[] { 0x9b6bd6, 0xf2f0ff, 0xf5c542 }                 // crocuses
                : Year < 0.46f ? new uint[] { 0xf7d23e, 0xfbfbf7, 0xd8a7e8, 0xf7d23e }    // dandelion, daisy, lady's smock
                : Year < 0.63f ? new uint[] { 0xe63b2e, 0x4a6fe0, 0xfbfbf7, 0xf1d04a }    // poppy, cornflower, daisy, buttercup
                : new uint[] { 0xb46ab8, 0xc98ad0 };                                      // heather
        }
    }

    /// Fireflies, in their weeks around midsummer, on warm evenings.
    public float Fireflies { get { return Warm ? Bump(Year, 0.45f, 0.47f, 0.53f, 0.56f) : 0; } }

    /// Rises from a to b, holds, falls from c to d.
    public static float Bump(float x, float a, float b, float c, float d)
    {
        return Col.Smoothstep(a, b, x) * (1 - Col.Smoothstep(c, d, x));
    }
}
