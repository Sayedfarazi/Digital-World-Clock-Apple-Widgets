import Foundation

/// User-facing options shared by every widget kind (set per widget in "Edit Widget").
struct ClockOptions: Equatable {
    var style: ClockStyle = .analog
    var showsSeconds = true
    var hourCycle: HourCycle = .system
    /// True inside the widget: digits, AM/PM, seconds and the VoiceOver time are live text, which the system
    /// keeps current. (Analog hands are always drawn from the entry's date; see `TimelinePlan`.)
    var live = false
    /// Analog faces: draw a second hand when `showsSeconds` is on. Off everywhere the widget is shown or
    /// previewed, because a widget's second hand would stand still (ARCHITECTURE §4). Only the calibration
    /// render against Apple's screenshot turns it on.
    var analogSecondHand = false
    var appearance = ClockAppearance()

    var twelveHour: Bool { hourCycle.uses12Hour() }
}

/// Everything a single clock needs to draw itself at a given instant.
struct CityClock: Identifiable, Equatable {
    /// Position in the widget (a city may legitimately appear twice).
    let index: Int
    let city: City
    let date: Date
    let isDaytime: Bool
    /// "Today" / "Tomorrow" / "Yesterday".
    let dayLabel: String
    /// "+0HRS", "-3HRS", "+10:30".
    let offsetLabel: String

    var id: Int { index }
    var timeZone: TimeZone { city.timeZone }

    init(index: Int = 0, city: City, date: Date, local: TimeZone = .autoupdatingCurrent) {
        self.index = index
        self.city = city
        self.date = date
        let zone = city.timeZone
        self.isDaytime = ClockMath.isDaytime(at: date, city: city)
        self.dayLabel = ClockText.dayLabel(delta: ClockMath.dayDelta(at: date, city: zone, local: local))
        self.offsetLabel = ClockText.offsetLabel(seconds: ClockMath.offsetSeconds(at: date, city: zone, local: local))
    }

    static func list(_ cities: [City], date: Date, local: TimeZone = .autoupdatingCurrent) -> [CityClock] {
        cities.enumerated().map { CityClock(index: $0.offset, city: $0.element, date: date, local: local) }
    }
}
