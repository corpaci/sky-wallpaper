// Port of Sources/wallframes/Extras.swift. Keep the two in step.

using System;
using System.Security.Cryptography;
using System.Text;

/// Secret words that change how the sky behaves, given with --extra. Only
/// salted, stretched hashes of them are kept, so the source names neither the
/// words nor which hash does what. Words are case-sensitive.
static class Extras
{
    static readonly string[] Known =
    {
        "ba76d161a68fa2d315d06549ac3a212cb49474119949012fb4da6146b8ba4ed9",
    };

    /// The word's bit (1 << its place in Known), or 0 for a word that isn't one.
    public static uint Bit(string word)
    {
        string h = Hash(word);
        for (int i = 0; i < Known.Length; i++) if (Known[i] == h) return 1u << i;
        return 0;
    }

    static string Hash(string word)
    {
        using (SHA256 sha = SHA256.Create())
        {
            byte[] h = sha.ComputeHash(Encoding.UTF8.GetBytes("sky-wallpaper/extra/" + word));
            for (int i = 1; i < 100000; i++) h = sha.ComputeHash(h);
            var hex = new StringBuilder(64);
            foreach (byte b in h) hex.Append(b.ToString("x2"));
            return hex.ToString();
        }
    }
}
