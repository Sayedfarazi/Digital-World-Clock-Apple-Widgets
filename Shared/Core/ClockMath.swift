import Foundation

/// Pure time math shared by the widget, the app and the unit tests.
enum ClockMath {
    /// Hand angles in degrees, clockwise from 12 o'clock.
    struct HandAngles: Equatable {
        var hour: Double
        var minute: Double
        var second: Double
    }

    static func calendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// Wall-clock seconds elapsed since local midnight in `timeZone` (0 ..< 86_400, DST-aware).
    static func secondsSinceMidnight(_ date: Date, in timeZone: TimeZone) -> Double {
        let c = calendar(timeZone).dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return Double(c.hour ?? 0) * 3600 + Double(c.minute ?? 0) * 60 + Double(c.second ?? 0)
            + Double(c.nanosecond ?? 0) / 1_000_000_000
    }

    static func handAngles(at date: Date, in timeZone: TimeZone) -> HandAngles {
        let s = secondsSinceMidnight(date, in: timeZone)
        return HandAngles(
            hour: s.truncatingRemainder(dividingBy: 43_200) / 43_200 * 360,
            minute: s.truncatingRemainder(dividingBy: 3_600) / 3_600 * 360,
            second: s.truncatingRemainder(dividingBy: 60) / 60 * 360
        )
    }

    /// Apple's World Clock widget rule: a white face while the sun is up in the city (sunrise to sunset, from
    /// the city's coordinates; see SunCalculator), a dark face otherwise. A city without coordinates (one
    /// synthesized from a time zone) falls back to the Clock app's rule, 6:00 to 17:59.
    static func isDaytime(at date: Date, city: City) -> Bool {
        guard city.hasCoordinates else { return isDaytime(at: date, in: city.timeZone) }
        return SunCalculator.isSunUp(at: date, latitude: city.lat, longitude: city.lon)
    }

    /// The Clock app's rule, used for cities without coordinates: white from 6:00 to 17:59 local time.
    static func isDaytime(at date: Date, in timeZone: TimeZone) -> Bool {
        let hour = calendar(timeZone).component(.hour, from: date)
        return hour >= 6 && hour < 18
    }

    /// Instants in (start, end] where a city's face colour changes: its sunrises and sunsets (or 06:00 and
    /// 18:00 for a city without coordinates, which `transitionDates` covers).
    static func daylightTransitions(after start: Date, until end: Date, cities: [City]) -> [Date] {
        var result = Set<Date>()
        var seen = Set<String>()
        for city in cities where city.hasCoordinates && seen.insert(city.id).inserted {
            result.formUnion(SunCalculator.events(after: start, until: end, latitude: city.lat, longitude: city.lon))
        }
        return result.sorted()
    }

    /// Calendar-day difference between the city and the viewer: 0 = Today, 1 = Tomorrow, -1 = Yesterday.
    static func dayDelta(at date: Date, city: TimeZone, local: TimeZone) -> Int {
        let a = calendar(city).dateComponents([.year, .month, .day], from: date)
        let b = calendar(local).dateComponents([.year, .month, .day], from: date)
        let utc = calendar(TimeZone(identifier: "UTC")!)
        guard let dayA = utc.date(from: a), let dayB = utc.date(from: b) else { return 0 }
        return utc.dateComponents([.day], from: dayB, to: dayA).day ?? 0
    }

    /// City UTC offset minus viewer UTC offset, in seconds, at `date` (DST-aware).
    static func offsetSeconds(at date: Date, city: TimeZone, local: TimeZone) -> Int {
        city.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
    }

    /// Every instant in (start, end] where something a clock draws from its timeline entry can change:
    /// - midnight in each city's zone and in the viewer's zone (the day label),
    /// - a daylight-saving change in any of those zones (the offset label),
    /// - a sunrise or sunset in a city with coordinates (the face colour),
    /// - 06:00 and 18:00 in a city without coordinates (its face colour, by the Clock app's rule).
    /// Digits, AM/PM and seconds need no entries: they're live text. Analog hands do (see `TimelinePlan`).
    static func transitionDates(after start: Date, until end: Date, cities: [City], local: TimeZone) -> [Date] {
        var result = Set<Date>()
        var seen = Set<String>()
        func add(hour: Int, in zone: TimeZone) {
            let cal = calendar(zone)
            var cursor = start
            while let next = cal.nextDate(after: cursor, matching: DateComponents(hour: hour, minute: 0, second: 0),
                                          matchingPolicy: .nextTime),
                  next <= end {
                result.insert(next)
                cursor = next
            }
        }
        for zone in cities.map(\.timeZone) + [local] where seen.insert(zone.identifier).inserted {
            add(hour: 0, in: zone)
            var cursor = start
            while let transition = zone.nextDaylightSavingTimeTransition(after: cursor), transition <= end {
                result.insert(transition)
                cursor = transition
            }
        }
        var noCoordinateZones = Set<String>()
        for city in cities where !city.hasCoordinates && noCoordinateZones.insert(city.tz).inserted {
            add(hour: 6, in: city.timeZone)
            add(hour: 18, in: city.timeZone)
        }
        result.formUnion(daylightTransitions(after: start, until: end, cities: cities))
        return result.filter { $0 > start && $0 <= end }.sorted()
    }

    /// Next whole minute strictly after `date`.
    static func nextMinute(after date: Date) -> Date {
        let t = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (floor(t / 60) + 1) * 60)
    }
}
