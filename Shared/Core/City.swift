import Foundation

/// One world-clock city. The list is a snapshot of Apple's own Clock city database
/// (see `Shared/scripts/gen_cities.py` and `Shared/Resources/cities.json`), so names and
/// abbreviations match the built-in macOS World Clock widget exactly.
struct City: Codable, Hashable, Identifiable, Sendable {
    /// Apple CityInfo.db identifier (stable). Synthesized cities use "tz:<identifier>".
    let id: String
    /// Display name, e.g. "New York".
    let name: String
    /// Short label used where space is tight, e.g. "NYC", "LA", "KOL".
    let abbr: String
    /// IANA (or legacy alias) time-zone identifier, e.g. "America/New_York", "US/Pacific".
    let tz: String
    /// Country / region shown as a subtitle in pickers, e.g. "U.S.A.".
    let country: String
    let lat: Double
    let lon: Double

    var timeZone: TimeZone { TimeZone(identifier: tz) ?? .current }

    /// Apple's cities have coordinates; cities synthesized from a time zone don't (0, 0).
    var hasCoordinates: Bool { lat != 0 || lon != 0 }

    /// "New York, U.S.A." — used as picker subtitle / accessibility label.
    var nameWithCountry: String { country.isEmpty ? name : "\(name), \(country)" }
}

extension City {
    /// A city derived purely from a time-zone identifier, for zones Apple's list doesn't cover
    /// (e.g. "America/Indiana/Indianapolis" -> "Indianapolis").
    static func synthesized(for timeZone: TimeZone) -> City {
        let identifier = timeZone.identifier
        let last = identifier.split(separator: "/").last.map(String.init) ?? identifier
        let name = last.replacingOccurrences(of: "_", with: " ")
        let letters = name.filter { $0.isLetter }
        let abbr = String(letters.prefix(3)).uppercased()
        return City(id: "tz:\(identifier)", name: name, abbr: abbr.isEmpty ? "TZ" : abbr,
                    tz: identifier, country: "", lat: 0, lon: 0)
    }
}
