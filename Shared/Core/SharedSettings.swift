import Foundation

/// Settings shared between the host app (writer) and the widget extension (reader).
///
/// macOS: the app is not sandboxed, so it writes its normal preferences domain
/// (~/Library/Preferences/<APP_BUNDLE_ID>.plist). The sandboxed widget reads that domain through the
/// `com.apple.security.temporary-exception.shared-preference.read-only` entitlement
/// (macOS/Resources/Widget/Widget.entitlements) — the same mechanism Apple's World Clock widget uses to read the
/// Clock app's city list. No App Group / provisioning profile is needed, which keeps local ad-hoc builds working.
///
/// iOS: the app and the widget share an App Group, named in both Info.plists (`WCWAppGroupIdentifier`, set from
/// iOS/Config/Base.xcconfig). Without the App Group entitlement each side gets defaults of its own, and the
/// widgets show the default list and the cities picked in Edit Widget.
enum SharedSettings {
    static let cityIDsKey = "worldClockCityIDs"
    static let clickActionKey = "widgetClickAction"
    static let cityWidgetCityKey = "cityWidgetCityID"
    /// Widget clicks open `worldclockwidgets://open[?city=<id>]` in the host app (macOS/config/project.env URL_SCHEME).
    static let urlScheme = "worldclockwidgets"

    /// Host app bundle identifier. The widget's Info.plist carries it as `WCWHostAppBundleIdentifier`.
    static var hostBundleIdentifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "WCWHostAppBundleIdentifier") as? String)
            ?? Bundle.main.bundleIdentifier ?? "com.worldclockwidgets.app"
    }

    private static var isHostApp: Bool { Bundle.main.bundleIdentifier == hostBundleIdentifier }

    /// macOS: `.standard` inside the app; the app's domain (read-only) inside the widget.
    /// iOS: the App Group's defaults, in the app and in the widget.
    static var store: UserDefaults {
        #if os(iOS)
        if let group = Bundle.main.object(forInfoDictionaryKey: "WCWAppGroupIdentifier") as? String,
           let defaults = UserDefaults(suiteName: group) {
            return defaults
        }
        return .standard
        #else
        if isHostApp { return .standard }
        return UserDefaults(suiteName: hostBundleIdentifier) ?? .standard
        #endif
    }

    /// The user's World Clock list, or nil if the user never edited it.
    static func storedCityIDs() -> [String]? {
        store.stringArray(forKey: cityIDsKey)
    }

    static func setCityIDs(_ ids: [String]) {
        store.set(ids, forKey: cityIDsKey)
    }

    /// The city "City" widgets show when no city is picked in Edit Widget; nil = this device's city.
    static var cityWidgetCityID: String? {
        get { store.string(forKey: cityWidgetCityKey) }
        set {
            if let newValue { store.set(newValue, forKey: cityWidgetCityKey) } else { store.removeObject(forKey: cityWidgetCityKey) }
        }
    }

    /// What a click on a widget does (macOS; on iOS a tap always opens the app).
    enum ClickAction: String, CaseIterable {
        case openClockApp      // Apple's widget behaviour: open Clock > World Clock
        case openThisApp

        var title: String {
            switch self {
            case .openClockApp: return "Clock"
            case .openThisApp: return "Digital World-Clock Widgets"
            }
        }
    }

    static var clickAction: ClickAction {
        get { ClickAction(rawValue: store.string(forKey: clickActionKey) ?? "") ?? .openClockApp }
        set { store.set(newValue.rawValue, forKey: clickActionKey) }
    }
}

/// Default city choices, used until the user picks cities (in the app or per widget via Edit Widget).
enum DefaultCities {
    /// New York, Los Angeles, Dhaka and Berlin (ids from Shared/Resources/cities.json). The device's own city
    /// always comes first.
    static let seedIDs = ["199", "152", "78", "37"]

    /// Extra well-known cities used to fill larger widgets (8 / 12 slots) when no list is configured.
    /// London, Tokyo, Sydney, Dubai, Singapore, Paris, Hong Kong, São Paulo, Chicago, Honolulu, Moscow, Auckland
    /// (ids from Shared/Resources/cities.json; unit tests verify they resolve).
    static let fillerIDs = ["149", "295", "287", "90", "277", "222", "118", "272", "67", "119", "186", "20"]

    /// The World Clock list: the user's list from the app, or the seed list.
    static func worldClockList(database: CityDatabase = .shared) -> [City] {
        if let stored = SharedSettings.storedCityIDs() {
            let cities = stored.compactMap { database.city(id: $0) }
            if !cities.isEmpty { return cities }
        }
        return seedList(database: database)
    }

    /// The device's city, then the seed cities, one clock per time zone: two cities in one zone would show the
    /// same time. A seed city in the device's own zone takes the first place under its own name (Los Angeles,
    /// for a device whose city is Cupertino: US/Pacific is another name of that zone). `local` is for tests; it
    /// defaults to the device's city.
    static func seedList(database: CityDatabase = .shared, local: City? = nil) -> [City] {
        let local = local ?? database.localCity
        let seeds = seedIDs.compactMap { database.city(id: $0) }
        var result = [seeds.first(where: { TimeZoneCanonicalizer.sameZone($0.tz, local.tz) }) ?? local]
        for city in seeds where !result.contains(where: { $0.id == city.id || TimeZoneCanonicalizer.sameZone($0.tz, city.tz) }) {
            result.append(city)
        }
        return result
    }

    /// The clocks of a World Clock widget with `capacity` clocks. Edit Widget shows one city row per clock: the
    /// rows picked there come first, and the rows left empty show the rest of `list` (the app's list), without
    /// repeating a picked city.
    static func slots(picked: [City], list: [City], capacity: Int) -> [City] {
        let picked = Array(picked.prefix(capacity))
        let rest = list.filter { city in !picked.contains { $0.id == city.id } }
        return picked + rest.prefix(max(0, capacity - picked.count))
    }

    /// `list` padded with well-known cities (no duplicates) up to `count`.
    static func filled(_ list: [City], to count: Int, database: CityDatabase = .shared) -> [City] {
        guard list.count < count else { return Array(list.prefix(count)) }
        var result = list
        for id in fillerIDs where result.count < count {
            if let city = database.city(id: id), !result.contains(where: { $0.id == city.id }) {
                result.append(city)
            }
        }
        return result
    }
}
