import Foundation

/// Read-only access to the bundled city list (`cities.json`).
/// Thread-safe: everything is immutable after init.
final class CityDatabase: @unchecked Sendable {
    let cities: [City]
    private let byID: [String: City]
    private let tzToCityID: [String: String]
    /// Canonical zone (see `TimeZoneCanonicalizer`) -> city id, for zones known under another name.
    private let canonicalZoneToCityID: [String: String]
    private let searchKeys: [(city: City, name: String, words: [String], countries: [String], abbr: String)]
    /// Normalized `City.optionValue` -> city id (Edit Widget values; see WidgetOptions.swift).
    let cityIDsByOptionValue: [String: String]

    private struct Payload: Decodable {
        let cities: [City]
        let tzToCity: [String: String]
    }

    /// The database bundled with the running app / widget extension.
    static let shared: CityDatabase = {
        if let url = Bundle.main.url(forResource: "cities", withExtension: "json"),
           let db = try? CityDatabase(contentsOf: url) {
            return db
        }
        // Should never happen in a correctly built bundle; keep the widget alive regardless.
        return CityDatabase(cities: [], tzToCity: [:])
    }()

    convenience init(contentsOf url: URL) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: url))
        self.init(cities: payload.cities, tzToCity: payload.tzToCity)
    }

    init(cities: [City], tzToCity: [String: String]) {
        self.cities = cities
        var map: [String: City] = [:]
        for city in cities { map[city.id] = city }
        self.byID = map
        self.tzToCityID = tzToCity
        self.canonicalZoneToCityID = CityDatabase.canonicalZoneMap(cities: cities, tzToCity: tzToCity, byID: map)
        self.searchKeys = cities.map { city in
            let name = CityDatabase.searchForm(city.name)
            let countries = ([city.country] + (CityDatabase.countryAliases[city.country] ?? [])).map(CityDatabase.searchForm)
            return (city, name, name.split(separator: " ").map(String.init), countries, CityDatabase.searchForm(city.abbr))
        }
        var byOptionValue: [String: String] = [:]
        for city in cities { byOptionValue[CityDatabase.normalize(city.optionValue)] = city.id }
        self.cityIDsByOptionValue = byOptionValue
    }

    // MARK: Lookup

    /// Resolves an id from `City.id`, including synthesized "tz:" ids.
    func city(id: String) -> City? {
        if let city = byID[id] { return city }
        if id.hasPrefix("tz:"), let tz = TimeZone(identifier: String(id.dropFirst(3))) {
            return City.synthesized(for: tz)
        }
        return nil
    }

    /// The city Apple's Clock would use to represent a time zone (e.g. America/New_York -> New York).
    /// Other names of the same zone resolve to the same city (Asia/Kolkata -> Mumbai, like Asia/Calcutta).
    /// A zone Apple's list doesn't cover gets a city named after the zone (America/Indiana/Knox -> Knox),
    /// never a different place that merely shares its offset.
    func city(for timeZone: TimeZone) -> City {
        let identifier = timeZone.identifier
        if let id = tzToCityID[identifier], let city = byID[id] { return city }
        if let city = cities.first(where: { $0.tz == identifier }) { return city }
        if let canonical = TimeZoneCanonicalizer.canonicalIdentifier(identifier),
           let id = canonicalZoneToCityID[canonical], let city = byID[id] {
            return city
        }
        return City.synthesized(for: timeZone)
    }

    /// Builds `canonicalZoneToCityID`. Apple's zone -> city table wins; within it, an entry whose zone is
    /// already canonical wins over its aliases. Then every city's own zone, in file order.
    private static func canonicalZoneMap(cities: [City], tzToCity: [String: String],
                                         byID: [String: City]) -> [String: String] {
        var map: [String: String] = [:]
        for zone in tzToCity.keys.sorted() {
            guard let id = tzToCity[zone], byID[id] != nil,
                  let canonical = TimeZoneCanonicalizer.canonicalIdentifier(zone) else { continue }
            if zone == canonical || map[canonical] == nil { map[canonical] = id }
        }
        for city in cities {
            guard let canonical = TimeZoneCanonicalizer.canonicalIdentifier(city.tz), map[canonical] == nil else { continue }
            map[canonical] = city.id
        }
        return map
    }

    /// The user's own city, derived from the device's current time zone.
    var localCity: City { city(for: TimeZone.current) }

    // MARK: Search

    /// Case-, diacritic- and punctuation-insensitive search over the name, the words in the name, the
    /// abbreviation and the country, including common other names of the country ("USA", "United States", "UK").
    /// Ranking: exact name > name prefix > word prefix > abbreviation > country > anywhere in the name;
    /// alphabetical within a rank.
    func search(_ query: String, limit: Int = .max) -> [City] {
        let q = CityDatabase.searchForm(query)
        guard !q.isEmpty else { return Array(cities.sorted { $0.name < $1.name }.prefix(limit)) }
        var ranked: [(rank: Int, city: City)] = []
        for key in searchKeys {
            let rank: Int
            if key.name == q { rank = 0 }
            else if key.name.hasPrefix(q) { rank = 1 }
            else if key.words.contains(where: { $0.hasPrefix(q) }) { rank = 2 }
            else if key.abbr == q { rank = 3 }
            else if key.countries.contains(where: { $0.hasPrefix(q) || $0.contains(" " + q) }) { rank = 4 }
            else if key.name.contains(q) { rank = 5 }
            else { continue }
            ranked.append((rank, key.city))
        }
        ranked.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.city.name < $1.city.name }
        return ranked.prefix(limit).map(\.city)
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    /// `normalize`d, without punctuation, words separated by single spaces: "U.S.A." -> "usa",
    /// "St. John's" -> "st johns", "Guinea-Bissau" -> "guinea bissau".
    static func searchForm(_ s: String) -> String {
        var out = ""
        var pendingSpace = false
        for ch in normalize(s) {
            if ch.isLetter || ch.isNumber {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(ch)
            } else if ch.isWhitespace || ch == "-" || ch == "/" || ch == "," || ch == "(" || ch == ")" || ch == "&" {
                pendingSpace = true
            }
            // Other punctuation (periods, apostrophes) is dropped without a break: "U.S.A." -> "usa".
        }
        return out
    }

    /// Other names people search for, by the country name Apple's list uses.
    static let countryAliases: [String: [String]] = [
        "U.S.A.": ["US", "United States", "United States of America", "America"],
        "U.S. Virgin Islands": ["USVI", "United States Virgin Islands"],
        "U.A.E.": ["United Arab Emirates", "Emirates"],
        "England": ["UK", "United Kingdom", "Great Britain", "Britain", "GB"],
        "Scotland": ["UK", "United Kingdom", "Great Britain", "Britain", "GB"],
        "Wales": ["UK", "United Kingdom", "Great Britain", "Britain", "GB"],
        "China mainland": ["China", "PRC", "People's Republic of China"],
        "Hong Kong SAR, China": ["Hong Kong"],
        "Macao SAR, China": ["Macau", "Macao"],
        "South Korea": ["Korea", "Republic of Korea"],
        "North Korea": ["Korea", "DPRK"],
        "Burma": ["Myanmar"],
        "Türkiye": ["Turkey"],
        "Czech Republic": ["Czechia"],
        "Swaziland": ["Eswatini"],
        "Côte d'Ivoire": ["Ivory Coast"],
        "East Timor": ["Timor-Leste"],
        "Cape Verde": ["Cabo Verde"],
        "Surinam": ["Suriname"],
        "Netherlands": ["Holland"],
        "Russia": ["Russian Federation"],
        "Democratic Republic of the Congo": ["DRC", "DR Congo", "Congo-Kinshasa"],
        "Congo": ["Republic of the Congo", "Congo-Brazzaville"],
        "Micronesia": ["Federated States of Micronesia"],
        "Vietnam": ["Viet Nam"],
        "Bailiwick of Jersey": ["Jersey", "Channel Islands"],
        "Guernsey": ["Channel Islands"],
    ]
}
