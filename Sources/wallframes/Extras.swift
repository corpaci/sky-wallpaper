import CryptoKit
import Foundation

/// Secret words that change how the sky behaves, given with --extra. Only
/// salted, stretched hashes of them are kept, so the source names neither the
/// words nor which hash does what. Words are case-sensitive.
enum Extras {
    private static let known = [
        "ba76d161a68fa2d315d06549ac3a212cb49474119949012fb4da6146b8ba4ed9",
    ]

    /// The word's bit (1 << its place in `known`), or 0 for a word that isn't one.
    static func bit(_ word: String) -> UInt32 {
        let h = hash(word)
        guard let i = known.firstIndex(of: h) else { return 0 }
        return UInt32(1) << UInt32(i)
    }

    private static func hash(_ word: String) -> String {
        var h = Data(SHA256.hash(data: Data(("sky-wallpaper/extra/" + word).utf8)))
        for _ in 1..<100_000 { h = Data(SHA256.hash(data: h)) }
        return h.map { String(format: "%02x", $0) }.joined()
    }
}
