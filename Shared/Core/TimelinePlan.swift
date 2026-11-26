import Foundation

/// The dates of one widget timeline.
///
/// **Digital faces** (`Mode.liveText`): the time, AM/PM and seconds are live text that the system updates by
/// itself, so an entry is only needed where something drawn from the entry's date changes: a face colour, a
/// day label or an offset label (`ClockState`). Candidate instants come from `ClockMath.transitionDates`, and
/// each is kept only if the state of some clock actually changes there.
///
/// **Analog faces** (`Mode.everyMinute`): macOS doesn't animate a third-party widget's clock hands (WidgetKit
/// leaves its clock-hand effect out of our archives; ARCHITECTURE §4), so the hands are drawn from each entry's
/// date and every minute gets an entry, plus the exact instants where a face colour or label changes.
///
/// Size limit: chronod stores every entry pre-rendered, in four variants, and drops a timeline whose archive
/// exceeds 10 MiB ("failed with too large timeline archive"; ChronoCore compares the size with 0xA00000).
/// Measured on macOS 27.2, per clock and entry: about 77 KB for a live digital face in an extra-large widget
/// (44 KB in a medium one) and about 24 KB for a static analog face. So a timeline holds at most
/// `clockEntryBudget(mode)` clocks over all its entries: 48 for live text (3.7 MB for the extra-large widget)
/// and 300 for analog (about 7 MB). Then it ends at its last entry, and WidgetKit asks for the next one
/// (policy `.atEnd`).
struct TimelinePlan: Equatable {
    var dates: [Date]

    enum Mode: String, Equatable {
        /// Digital: digits, AM/PM and seconds are live text. Entries only where a clock's state changes.
        case liveText
        /// Analog: hands drawn from the entry's date. An entry every minute.
        case everyMinute
    }

    /// Live text: a day per timeline, if the entry budget allows.
    static let liveHorizon: TimeInterval = 24 * 3600

    /// Clocks × entries per timeline (see the size limit above).
    static func clockEntryBudget(_ mode: Mode) -> Int {
        switch mode {
        case .liveText: return 48
        case .everyMinute: return 300
        }
    }

    /// Live text: 48 entries for a City widget, 12 for 4 clocks, 6 for 8, 4 for 12.
    /// Every minute: 300 minutes for a City widget, 75 for 4 clocks, 37 for 8, 25 for 12.
    static func maxEntries(clockCount: Int, mode: Mode) -> Int {
        max(2, clockEntryBudget(mode) / max(1, clockCount))
    }

    /// `limit` overrides `maxEntries` (tests).
    static func make(now: Date, cities: [City], local: TimeZone, mode: Mode, limit: Int? = nil) -> TimelinePlan {
        let limit = limit ?? maxEntries(clockCount: cities.count, mode: mode)
        switch mode {
        case .liveText:
            let horizon = now.addingTimeInterval(liveHorizon)
            var dates = [now]
            var state = ClockState.all(cities, at: now, local: local)
            for date in ClockMath.transitionDates(after: now, until: horizon, cities: cities, local: local) {
                guard dates.count < limit else { break }
                let next = ClockState.all(cities, at: date, local: local)
                if next != state {
                    dates.append(date)
                    state = next
                }
            }
            if dates.count < limit, let last = dates.last, last < horizon {
                dates.append(horizon)
            }
            return TimelinePlan(dates: dates)
        case .everyMinute:
            // Enough minutes to fill the budget, plus every exact change of a face colour or label in between.
            let horizon = now.addingTimeInterval(Double(limit) * 60)
            var candidates = Set(ClockMath.transitionDates(after: now, until: horizon, cities: cities, local: local))
            var minute = ClockMath.nextMinute(after: now)
            while minute <= horizon {
                candidates.insert(minute)
                minute = minute.addingTimeInterval(60)
            }
            return TimelinePlan(dates: [now] + candidates.filter { $0 > now }.sorted().prefix(limit - 1))
        }
    }
}

/// What a clock draws from its timeline entry's date, rather than live.
struct ClockState: Hashable {
    var isDaytime: Bool
    var dayDelta: Int
    var offsetSeconds: Int

    init(city: City, date: Date, local: TimeZone) {
        isDaytime = ClockMath.isDaytime(at: date, city: city)
        dayDelta = ClockMath.dayDelta(at: date, city: city.timeZone, local: local)
        offsetSeconds = ClockMath.offsetSeconds(at: date, city: city.timeZone, local: local)
    }

    static func all(_ cities: [City], at date: Date, local: TimeZone) -> [ClockState] {
        cities.map { ClockState(city: $0, date: date, local: local) }
    }
}
