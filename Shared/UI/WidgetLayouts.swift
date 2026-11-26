import SwiftUI
import WidgetKit

// Layouts for every widget kind and size. Shared by the widget extension, the app's previews and the
// snapshot renderer (macOS/scripts/render_snapshots.sh), so what you see in the app/snapshots is what the
// desktop shows. All metrics are in points at the nominal widget size and scale with the real size.

/// Measured from Apple's medium World Clock widget on macOS 27 (macOS/docs/DESIGN-SPEC.md).
enum WorldClockMetrics {
    /// Distance between column centres.
    static let columnPitch: CGFloat = 79
    static let faceDiameter: CGFloat = 71
    /// Gap between a face and the city name below it.
    static let faceToText: CGFloat = 4
    /// City / day / offset labels.
    static let fontSize: CGFloat = 11
    /// Apple's label lines are 12.75 pt apart; SwiftUI's natural line box for 11 pt is ~1.5 pt taller.
    static let lineSpacing: CGFloat = -1.5
    /// Apple's block sits ~1 pt below exact vertical centring.
    static let verticalBias: CGFloat = 1
    /// Horizontal margin outside the outer columns.
    static let sideMargin: CGFloat = 14

    /// Small World Clock (2 × 2).
    static let smallFaceDiameter: CGFloat = 62
    static let smallGap: CGFloat = 10

    /// Single City widget.
    static let cityFaceDiameter: CGFloat = 140

    /// Extra-large widgets have room to spare vertically; faces and labels grow a little.
    static let extraLargeScale: CGFloat = 1.15
}

/// One clock in the chosen style.
struct ClockFace: View {
    let clock: CityClock
    let options: ClockOptions
    let diameter: CGFloat
    var dial: DialStyle = .numerals
    /// Text inside the face (analog: abbreviation under the hub; digital: caption above the time).
    var label: String? = nil
    /// Digital only: a line under the time.
    var footnote: String? = nil
    /// Digital only: circle (World Clock) or rounded square (City).
    var digitalShape: DigitalFaceShape = .circle

    var body: some View {
        switch options.style {
        case .analog:
            AnalogClockFace(diameter: diameter, timeZone: clock.timeZone, date: clock.date,
                            isDaytime: clock.isDaytime, dial: dial, label: label,
                            showsSeconds: options.showsSeconds && options.analogSecondHand,
                            appearance: options.appearance)
        case .digital:
            DigitalClockFace(diameter: diameter, timeZone: clock.timeZone, date: clock.date,
                             isDaytime: clock.isDaytime, twelveHour: options.twelveHour, shape: digitalShape,
                             caption: label, footnote: footnote, showsSeconds: options.showsSeconds,
                             live: options.live, appearance: options.appearance)
        }
    }
}

// MARK: - World Clock

/// "World Clock" widget: up to 4 / 4 / 8 / 12 cities for small / medium / large / extra large.
struct WorldClockLayout: View {
    let family: ClockFamily
    let clocks: [CityClock]
    let options: ClockOptions
    let size: CGSize

    var body: some View {
        Group {
            if clocks.isEmpty {
                Text("No cities")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(options.appearance.secondaryLabel)
            } else {
                switch family {
                case .small: smallGrid
                case .medium: columns(perRow: 4, rows: 1, scale: unit)
                case .large: columns(perRow: 4, rows: 2, scale: unit)
                case .extraLarge: columns(perRow: 6, rows: 2, scale: unit * WorldClockMetrics.extraLargeScale)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// Real size relative to the nominal macOS size (1 on a standard display).
    private var unit: CGFloat {
        let nominal = family.nominalSize
        return max(0.5, min(size.width / nominal.width, size.height / nominal.height))
    }

    private var visibleClocks: [CityClock] { Array(clocks.prefix(family.worldClockCapacity)) }

    // Medium / large / extra large: rows of columns (face over name, day and offset), each row centred.
    private func columns(perRow: Int, rows: Int, scale: CGFloat) -> some View {
        let items = visibleClocks
        let rowCount = min(rows, (items.count + perRow - 1) / perRow)
        let chunks = (0..<rowCount).map { r in Array(items[(r * perRow)..<min(items.count, (r + 1) * perRow)]) }
        let available = size.width - 2 * WorldClockMetrics.sideMargin * unit
        let pitch = max(WorldClockMetrics.columnPitch * scale, perRow > 4 ? available / CGFloat(perRow) : 0)
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            ForEach(chunks.indices, id: \.self) { r in
                if r > 0 { Spacer(minLength: 0) }
                HStack(spacing: 0) {
                    ForEach(chunks[r]) { clock in
                        WorldClockColumn(clock: clock, options: options, scale: scale, width: pitch)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .offset(y: WorldClockMetrics.verticalBias * scale)
    }

    // Small: 2 × 2 grid of faces with the city abbreviation inside each face.
    @ViewBuilder
    private var smallGrid: some View {
        let items = Array(visibleClocks.prefix(4))
        let d = WorldClockMetrics.smallFaceDiameter * unit
        let gap = WorldClockMetrics.smallGap * unit
        if items.count == 1, let only = items.first {
            CityLayout(clock: only, options: options, size: size)
        } else {
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    ForEach(items.prefix(2)) { smallFace($0, diameter: d) }
                }
                if items.count > 2 {
                    HStack(spacing: gap) {
                        ForEach(items.dropFirst(2)) { smallFace($0, diameter: d) }
                    }
                }
            }
        }
    }

    private func smallFace(_ clock: CityClock, diameter: CGFloat) -> some View {
        ClockFace(clock: clock, options: options, diameter: diameter, dial: .ticks, label: clock.city.abbr)
            .clockAccessibility(clock, options: options)
    }
}

/// Face with "City / Today / +3HRS" underneath — one column of the medium/large/XL World Clock.
struct WorldClockColumn: View {
    let clock: CityClock
    let options: ClockOptions
    let scale: CGFloat
    let width: CGFloat

    var body: some View {
        VStack(spacing: WorldClockMetrics.faceToText * scale) {
            ClockFace(clock: clock, options: options, diameter: WorldClockMetrics.faceDiameter * scale)
            VStack(spacing: WorldClockMetrics.lineSpacing * scale) {
                Text(clock.city.name)
                    .font(.system(size: WorldClockMetrics.fontSize * scale, weight: .bold))
                    .foregroundStyle(options.appearance.primaryLabel)
                Group {
                    Text(clock.dayLabel)
                    Text(clock.offsetLabel)
                }
                .font(.system(size: WorldClockMetrics.fontSize * scale, weight: .semibold))
                .foregroundStyle(options.appearance.secondaryLabel)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: max(0, width - 4 * scale))
        }
        .frame(width: width)
        .clockAccessibility(clock, options: options)
    }
}

// MARK: - City

/// "City" widget: one large clock with the city's abbreviation (analog) or name (digital) on the face.
struct CityLayout: View {
    let clock: CityClock
    let options: ClockOptions
    let size: CGSize

    var body: some View {
        let d = min(WorldClockMetrics.cityFaceDiameter * min(size.width / 162, size.height / 162),
                    min(size.width, size.height) - 12)
        Group {
            switch options.style {
            case .analog:
                ClockFace(clock: clock, options: options, diameter: d, dial: .numeralsAndTicks,
                          label: clock.city.abbr)
            case .digital:
                ClockFace(clock: clock, options: options, diameter: d, label: clock.city.name,
                          footnote: "\(clock.dayLabel), \(clock.offsetLabel)", digitalShape: .roundedSquare)
            }
        }
        .frame(width: size.width, height: size.height)
        .clockAccessibility(clock, options: options)
    }
}

extension CityClock {
    /// "Berlin, Today, +6HRS".
    var accessibilityText: String { "\(city.name), \(dayLabel), \(offsetLabel)" }

    /// The city's time, as VoiceOver reads it ("9:19 PM" or "21:19"). In the widget it is live text, like the
    /// digits, so it stays current between timeline entries; a string made from the entry's date would not.
    func accessibilityTime(options: ClockOptions) -> Text {
        let style = ClockText.spokenTimeStyle(timeZone: timeZone, twelveHour: options.twelveHour)
        return options.live ? Text(.currentDate, format: style) : Text(date, format: style)
    }
}

extension View {
    /// One accessibility element per clock: label "Berlin, Today, +6HRS", value the city's current time.
    /// `Text(date, format:)` formats in the environment's time zone, hence `inTimeZone` (CLAUDE.md rule 4).
    func clockAccessibility(_ clock: CityClock, options: ClockOptions) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(clock.accessibilityText))
            .accessibilityValue(clock.accessibilityTime(options: options))
            .inTimeZone(clock.timeZone)
    }
}
