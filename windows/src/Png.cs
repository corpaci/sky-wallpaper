// Minimal PNG writer: 8-bit RGB, one IDAT, Up filter, tagged sRGB. Hand-rolled
// so the same code runs on .NET Framework (Windows) and on Mono (parity checks
// on a Mac), and writes the dither bytes exactly as rendered.

using System.IO;
using System.IO.Compression;

static class Png
{
    static readonly uint[] crcTable = MakeCrcTable();

    public static void Write(string path, byte[] rgb, int width, int height)
    {
        int stride = width * 3;
        var filtered = new byte[(stride + 1) * height];
        for (int y = 0; y < height; y++)
        {
            int o = y * (stride + 1), row = y * stride;
            filtered[o] = 2;  // Up: smooth vertical gradients turn into small residuals
            for (int i = 0; i < stride; i++)
                filtered[o + 1 + i] = unchecked((byte)(rgb[row + i] - (y > 0 ? rgb[row - stride + i] : 0)));
        }

        byte[] zlib;
        using (var ms = new MemoryStream())
        {
            ms.WriteByte(0x78);
            ms.WriteByte(0x9c);
            using (var deflate = new DeflateStream(ms, CompressionMode.Compress, true))
                deflate.Write(filtered, 0, filtered.Length);
            WriteBE(ms, Adler32(filtered));
            zlib = ms.ToArray();
        }

        var header = new MemoryStream();
        WriteBE(header, (uint)width);
        WriteBE(header, (uint)height);
        header.Write(new byte[] { 8, 2, 0, 0, 0 }, 0, 5);  // 8-bit, truecolor, deflate, no filter variant, no interlace

        using (var f = File.Create(path))
        {
            f.Write(new byte[] { 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a }, 0, 8);
            Chunk(f, "IHDR", header.ToArray());
            Chunk(f, "sRGB", new byte[] { 0 });
            Chunk(f, "IDAT", zlib);
            Chunk(f, "IEND", new byte[0]);
        }
    }

    static void Chunk(Stream s, string type, byte[] data)
    {
        var typed = new byte[4 + data.Length];
        for (int i = 0; i < 4; i++) typed[i] = (byte)type[i];
        data.CopyTo(typed, 4);
        WriteBE(s, (uint)data.Length);
        s.Write(typed, 0, typed.Length);
        WriteBE(s, Crc32(typed));
    }

    static void WriteBE(Stream s, uint v)
    {
        s.WriteByte((byte)(v >> 24));
        s.WriteByte((byte)(v >> 16));
        s.WriteByte((byte)(v >> 8));
        s.WriteByte((byte)v);
    }

    static uint[] MakeCrcTable()
    {
        var table = new uint[256];
        for (uint n = 0; n < 256; n++)
        {
            uint c = n;
            for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
            table[n] = c;
        }
        return table;
    }

    static uint Crc32(byte[] data)
    {
        uint c = 0xffffffff;
        foreach (byte b in data) c = crcTable[(c ^ b) & 0xff] ^ (c >> 8);
        return c ^ 0xffffffff;
    }

    static uint Adler32(byte[] data)
    {
        uint a = 1, b = 0;
        foreach (byte d in data)
        {
            a = (a + d) % 65521;
            b = (b + a) % 65521;
        }
        return (b << 16) | a;
    }
}
