import Foundation

/// 12/24-hour preference for digital clocks.
enum HourCycle: String, Codable, CaseIterable, Sendable {
    case system
    case twelveHour
    case twentyFourHour

    /// Resolves `.system` using the device's "24-hour time" setting (reflected in the locale's hour cycle).
    func uses12Hour(locale: Locale = .autoupdatingCurrent) -> Bool {
        switch self {
        case .twelveHour: return true
        case .twentyFourHour: return false
        case .system:
            switch locale.hourCycle {
            case .oneToTwelve, .zeroToEleven: return true
            case .zeroToTwentyThree, .oneToTwentyFour: return false
            @unknown default:
                let pattern = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
                return pattern.contains("h") || pattern.contains("K")
            }
        }
    }
}

/// Text shown on the clocks. Mirrors Apple's World Clock widget wording ("Today", "+3HRS", "+10:30").
enum ClockText {
    static func dayLabel(delta: Int) -> String {
        switch delta {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default: return delta > 0 ? "+\(delta) Days" : "\(delta) Days"
        }
    }

    /// Whole hours -> "+6HRS" / "-3HRS" / "+0HRS"; under an hour -> "+30MINS"; otherwise "+10:30".
    static func offsetLabel(seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let totalMinutes = abs(seconds) / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if minutes == 0 { return "\(sign)\(hours)HRS" }
        if hours == 0 { return "\(sign)\(minutes)MINS" }
        return "\(sign)\(hours):" + (minutes < 10 ? "0\(minutes)" : "\(minutes)")
    }

    // MARK: Digital time

    /// "1:53" (12-hour) or "13:53" (24-hour) in `timeZone`. Works live with `Text(.currentDate, format:)`.
    static func timeStyle(timeZone: TimeZone, twelveHour: Bool, showsSeconds: Bool = false,
                          locale: Locale = .autoupdatingCurrent) -> Date.VerbatimFormatStyle {
        let format: Date.FormatString
        switch (twelveHour, showsSeconds) {
        case (true, false):
            format = "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits)"
        case (true, true):
            format = "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits):\(second: .twoDigits)"
        case (false, false):
            format = "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
        case (false, true):
            format = "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits):\(second: .twoDigits)"
        }
        return Date.VerbatimFormatStyle(format: format, locale: locale, timeZone: timeZone,
                                        calendar: ClockMath.calendar(timeZone))
    }

    /// "1:53 PM" (12-hour) or "13:53" (24-hour) in `timeZone`: the time VoiceOver reads for a clock.
    static func spokenTimeStyle(timeZone: TimeZone, twelveHour: Bool,
                                locale: Locale = .autoupdatingCurrent) -> Date.VerbatimFormatStyle {
        let format: Date.FormatString = twelveHour
            ? "\(hour: .defaultDigits(clock: .twelveHour, hourCycle: .oneBased)):\(minute: .twoDigits) \(dayPeriod: .standard(.abbreviated))"
            : "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)"
        return Date.VerbatimFormatStyle(format: format, locale: locale, timeZone: timeZone,
                                        calendar: ClockMath.calendar(timeZone))
    }

    /// ":05": the seconds, shown under a digital time (in the accent colour). Works live with
    /// `Text(.currentDate, format:)`: the system updates such text every second.
    static func secondsStyle(timeZone: TimeZone, locale: Locale = .autoupdatingCurrent) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(format: ":\(second: .twoDigits)", locale: locale, timeZone: timeZone,
                                 calendar: ClockMath.calendar(timeZone))
    }

    /// "AM" / "PM" in `timeZone`.
    static func periodStyle(timeZone: TimeZone, locale: Locale = .autoupdatingCurrent) -> Date.VerbatimFormatStyle {
        Date.VerbatimFormatStyle(format: "\(dayPeriod: .standard(.abbreviated))", locale: locale,
                                 timeZone: timeZone, calendar: ClockMath.calendar(timeZone))
    }
}
