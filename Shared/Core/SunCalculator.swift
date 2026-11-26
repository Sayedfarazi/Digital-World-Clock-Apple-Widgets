import Foundation

/// The sun's position, sunrise and sunset for a place, computed like NOAA's solar calculator (after Jean Meeus,
/// "Astronomical Algorithms").
///
/// Apple's World Clock widget shows a white face while the sun is up in that city and a dark face otherwise.
/// It gets sunrise and sunset from GeoServices (`GEOAlmanac`, a private framework); this is a Foundation-only
/// equivalent. Its sunrise and sunset times match the ones the Clock app shows (unit-tested).
///
/// "Up" is decided at the instant, from the sun's altitude (`isSunUp`), and `events` are the instants where
/// that answer changes. Both use the same altitude, so they always agree, including on the days near the
/// polar day and the polar night when the sun barely rises or barely sets.
enum SunCalculator {
    /// The sun on one calendar day at one place.
    enum Day: Equatable {
        case normal(sunrise: Date, sunset: Date)
        /// Midnight sun: the sun stays above the horizon all day.
        case alwaysUp
        /// Polar night: the sun stays below the horizon all day.
        case alwaysDown
    }

    /// Standard sunrise and sunset: the sun's centre 0.833° below the horizon (refraction plus the sun's radius).
    static let horizonAltitude = -0.833

    /// The solar day whose noon is nearest to `localNoon` (12:00 on that day in the place's time zone).
    static func day(latitude: Double, longitude: Double, near localNoon: Date) -> Day {
        var noon = localNoon
        for _ in 0..<3 { noon = solarNoon(near: noon, longitude: longitude) }
        guard let halfDay = halfDayArc(latitude: latitude, at: noon) else {
            return isUp(latitude: latitude, at: noon) ? .alwaysUp : .alwaysDown
        }
        // Refine each event with the sun's position at that event (declination and equation of time change
        // a little over half a day).
        var sunrise = noon.addingTimeInterval(-halfDay)
        var sunset = noon.addingTimeInterval(halfDay)
        for _ in 0..<2 {
            if let arc = halfDayArc(latitude: latitude, at: sunrise) {
                sunrise = solarNoon(near: sunrise, longitude: longitude).addingTimeInterval(-arc)
            }
            if let arc = halfDayArc(latitude: latitude, at: sunset) {
                sunset = solarNoon(near: sunset, longitude: longitude).addingTimeInterval(arc)
            }
        }
        return .normal(sunrise: sunrise, sunset: sunset)
    }

    /// True if the sun's centre is above `horizonAltitude` at `date` at the given place.
    static func isSunUp(at date: Date, latitude: Double, longitude: Double) -> Bool {
        altitude(at: date, latitude: latitude, longitude: longitude) > horizonAltitude
    }

    /// The sun's altitude above the horizon, in degrees, at `date` at the given place (no refraction).
    static func altitude(at date: Date, latitude: Double, longitude: Double) -> Double {
        let sun = position(at: date)
        let utcMinutes = date.timeIntervalSince1970 / 60
        var trueSolarMinutes = (utcMinutes + sun.equationOfTime + 4 * longitude).truncatingRemainder(dividingBy: 1440)
        if trueSolarMinutes < 0 { trueSolarMinutes += 1440 }
        let hourAngle = radians(trueSolarMinutes / 4 - 180)
        let phi = radians(latitude), declination = radians(sun.declination)
        let sine = sin(phi) * sin(declination) + cos(phi) * cos(declination) * cos(hourAngle)
        return degrees(asin(max(-1, min(1, sine))))
    }

    /// Every sunrise and sunset in (start, end]: each instant where `isSunUp` changes, to within a quarter of a
    /// second. The returned instant is the first one with the new answer.
    ///
    /// The altitude is sampled every five minutes, and also at each solar noon and solar midnight, where it
    /// peaks and bottoms out. Near the polar night the sun can peek over the horizon for less than five minutes
    /// (Davis Station, 2027-07-10: up from 06:51:53 to 06:55:35 UTC): that is around solar noon, so the noon
    /// sample is up and both crossings are found. The same goes for a brief dip at solar midnight near the
    /// polar day.
    static func events(after start: Date, until end: Date, latitude: Double, longitude: Double) -> [Date] {
        guard end > start else { return [] }
        var samples = extremes(after: start, until: end, longitude: longitude)
        var t = start
        while t < end {
            t = min(t.addingTimeInterval(300), end)
            samples.append(t)
        }
        samples.sort()
        var result: [Date] = []
        var previous = start
        var wasUp = isSunUp(at: start, latitude: latitude, longitude: longitude)
        for next in samples where next > previous {
            let isUp = isSunUp(at: next, latitude: latitude, longitude: longitude)
            if isUp != wasUp {
                var low = previous, high = next // low has the old answer, high the new one
                while high.timeIntervalSince(low) > 0.25 {
                    let middle = low.addingTimeInterval(high.timeIntervalSince(low) / 2)
                    if isSunUp(at: middle, latitude: latitude, longitude: longitude) == isUp { high = middle } else { low = middle }
                }
                result.append(high)
                wasUp = isUp
            }
            previous = next
        }
        return result
    }

    /// The solar noons and solar midnights in (start, end): where the sun's altitude is highest and lowest.
    static func extremes(after start: Date, until end: Date, longitude: Double) -> [Date] {
        var result: [Date] = []
        var t = start
        while t < end.addingTimeInterval(43_200) {
            for hourAngle in [0.0, 180.0] {
                let instant = transit(near: t, longitude: longitude, hourAngle: hourAngle)
                if instant > start, instant < end, !result.contains(where: { abs($0.timeIntervalSince(instant)) < 1 }) {
                    result.append(instant)
                }
            }
            t = t.addingTimeInterval(43_200)
        }
        return result
    }

    /// The instant nearest to `date` at which the sun's hour angle is `hourAngle` degrees: 0 at solar noon,
    /// 180 at solar midnight.
    static func transit(near date: Date, longitude: Double, hourAngle target: Double) -> Date {
        var instant = date
        for _ in 0..<2 { // the second pass corrects for the equation of time at the transit itself
            let utcMinutes = instant.timeIntervalSince1970 / 60
            var trueSolarMinutes = (utcMinutes + position(at: instant).equationOfTime + 4 * longitude)
                .truncatingRemainder(dividingBy: 1440)
            if trueSolarMinutes < 0 { trueSolarMinutes += 1440 }
            var past = (trueSolarMinutes / 4 - 180 - target).truncatingRemainder(dividingBy: 360) // degrees past it
            if past > 180 { past -= 360 } else if past <= -180 { past += 360 }
            instant = instant.addingTimeInterval(-past * 240) // the sun moves 1° in 4 minutes
        }
        return instant
    }

    // MARK: Solar position

    /// Sun's declination (degrees) and equation of time (minutes) at `date`.
    static func position(at date: Date) -> (declination: Double, equationOfTime: Double) {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545.0) / 36_525 // Julian centuries since J2000.0
        let meanLongitude = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let meanAnomaly = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(radians(meanAnomaly)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * t)
            + sin(radians(3 * meanAnomaly)) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let apparentLongitude = meanLongitude + center - 0.00569 - 0.00478 * sin(radians(omega))
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(radians(omega))
        let declination = degrees(asin(sin(radians(obliquity)) * sin(radians(apparentLongitude))))
        let y = pow(tan(radians(obliquity / 2)), 2)
        let l0 = radians(meanLongitude), m = radians(meanAnomaly)
        let equationOfTime = 4 * degrees(y * sin(2 * l0) - 2 * eccentricity * sin(m)
            + 4 * eccentricity * y * sin(m) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0) - 1.25 * eccentricity * eccentricity * sin(2 * m))
        return (declination, equationOfTime)
    }

    /// The solar noon (sun due south or north) nearest to `date`.
    static func solarNoon(near date: Date, longitude: Double) -> Date {
        let utcMinutes = date.timeIntervalSince1970 / 60
        var trueSolarMinutes = (utcMinutes + position(at: date).equationOfTime + 4 * longitude)
            .truncatingRemainder(dividingBy: 1440)
        if trueSolarMinutes < 0 { trueSolarMinutes += 1440 }
        let hourAngle = trueSolarMinutes / 4 - 180 // degrees; 0 at solar noon, negative before it
        return date.addingTimeInterval(-hourAngle * 240) // the sun moves 1° in 4 minutes
    }

    /// Seconds from solar noon to sunset (= from sunrise to solar noon), or nil if the sun doesn't cross the
    /// horizon that day.
    private static func halfDayArc(latitude: Double, at date: Date) -> TimeInterval? {
        let declination = radians(position(at: date).declination)
        let phi = radians(latitude)
        let denominator = cos(phi) * cos(declination)
        guard abs(denominator) > 1e-12 else { return nil }
        let cosHourAngle = (sin(radians(horizonAltitude)) - sin(phi) * sin(declination)) / denominator
        guard cosHourAngle >= -1, cosHourAngle <= 1 else { return nil }
        return degrees(acos(cosHourAngle)) * 240
    }

    /// At a place where the sun doesn't cross the horizon: is it up (rather than down) at solar noon?
    private static func isUp(latitude: Double, at date: Date) -> Bool {
        let declination = radians(position(at: date).declination)
        let phi = radians(latitude)
        let altitude = degrees(asin(sin(phi) * sin(declination) + cos(phi) * cos(declination)))
        return altitude > horizonAltitude
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
