import Foundation

extension String {

    // MARK: - Language helpers

    /// Returns the localised language name for a 3-letter ISO 639-2 code.
    /// Example: `"ger"` → `"German"`, `"eng"` → `"English"`.
    var languageName: String? {
        Locale.current.localizedString(forLanguageCode: self)
    }

    /// Returns a flag emoji for the ISO 639-2 language code, falling back to 🌐.
    var languageFlag: String {
        let flags: [String: String] = [
            "eng": "🇬🇧",
            "ger": "🇩🇪", "deu": "🇩🇪",
            "fra": "🇫🇷", "fre": "🇫🇷",
            "spa": "🇪🇸",
            "ita": "🇮🇹",
            "por": "🇵🇹",
            "rus": "🇷🇺",
            "jpn": "🇯🇵",
            "chi": "🇨🇳", "zho": "🇨🇳",
            "kor": "🇰🇷",
            "ara": "🇸🇦",
            "hin": "🇮🇳",
            "tur": "🇹🇷",
            "pol": "🇵🇱",
            "nld": "🇳🇱", "dut": "🇳🇱",
            "swe": "🇸🇪",
            "nor": "🇳🇴",
            "dan": "🇩🇰",
            "fin": "🇫🇮",
            "ces": "🇨🇿", "cze": "🇨🇿",
            "hun": "🇭🇺",
            "ron": "🇷🇴", "rum": "🇷🇴",
            "hrv": "🇭🇷",
            "srp": "🇷🇸",
            "bul": "🇧🇬",
            "slk": "🇸🇰", "slo": "🇸🇰",
            "ukr": "🇺🇦",
            "heb": "🇮🇱",
            "tha": "🇹🇭",
            "vie": "🇻🇳",
            "ind": "🇮🇩",
            "msa": "🇲🇾", "may": "🇲🇾",
            "lat": "🏛️",
            "und": "🌐"
        ]
        return flags[lowercased()] ?? "🌐"
    }
}
