import Foundation

// The values of the Edit Widget options (Style, Time Format, City, Cities).
//
// The widget's parameters are plain Strings with option lists, not AppEnum / AppEntity types: an ad-hoc signed
// extension can't decode those (ARCHITECTURE §5). Each value is the label the user sees, so it reads well
// wherever the system shows it. Values saved by version 1.0 (enum raw values, city ids) still parse.

extension ClockStyle {
    /// The Style value in Edit Widget: "Analog" or "Digital".
    var optionValue: String {
        switch self {
        case .analog: return "Analog"
        case .digital: return "Digital"
        }
    }

    /// The choices offered in Edit Widget, in menu order.
    static var optionValues: [String] { allCases.map(\.optionValue) }

    /// The style for a saved Style value: "Analog" / "Digital", or a raw value saved by version 1.0.
    init?(optionValue: String) {
        let value = optionValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let style = ClockStyle.allCases.first(where: {
            $0.optionValue.caseInsensitiveCompare(value) == .orderedSame || $0.rawValue == value
        }) else { return nil }
        self = style
    }
}

extension HourCycle {
    /// The Time Format value in Edit Widget.
    var optionValue: String {
        switch self {
        case .system: return "System Setting"
        case .twelveHour: return "12-Hour"
        case .twentyFourHour: return "24-Hour"
        }
    }

    /// The choices offered in Edit Widget, in menu order.
    static var optionValues: [String] { allCases.map(\.optionValue) }

    /// The hour cycle for a saved Time Format value, or a raw value saved by version 1.0 ("twentyFourHour").
    init?(optionValue: String) {
        let value = optionValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let cycle = HourCycle.allCases.first(where: {
            $0.optionValue.caseInsensitiveCompare(value) == .orderedSame || $0.rawValue == value
        }) else { return nil }
        self = cycle
    }
}

extension City {
    /// The City value in Edit Widget: "Dhaka, Bangladesh", or "Name" for the few cities without a country.
    /// Unique across Apple's list (a unit test checks it). A city synthesized from a time zone, which only the
    /// device's own city or the app's list can contain, is "Knox (America/Indiana/Knox)".
    var optionValue: String {
        id.hasPrefix("tz:") ? "\(name) (\(tz))" : nameWithCountry
    }
}

extension CityDatabase {
    /// The city for a saved City value: its `optionValue` (any case or accents), or a `City.id`, which is
    /// what version 1.0 saved.
    func city(optionValue value: String) -> City? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if let id = cityIDsByOptionValue[CityDatabase.normalize(value)], let city = city(id: id) { return city }
        if let city = city(id: value) { return city }
        // "Knox (America/Indiana/Knox)": a city synthesized from a time zone.
        if value.hasSuffix(")"), let open = value.range(of: " (", options: .backwards) {
            let zone = String(value[open.upperBound..<value.index(before: value.endIndex)])
            if let city = city(id: "tz:\(zone)") { return city }
        }
        return nil
    }
}
