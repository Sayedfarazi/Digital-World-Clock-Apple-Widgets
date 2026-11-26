import SwiftUI
import WidgetKit

/// Outline of a digital face.
enum DigitalFaceShape {
    /// Same silhouette as the analog faces. Used by the World Clock widget, so analog and digital
    /// columns line up identically.
    case circle
    /// Rounded square with a 60-tick ring — the design of Apple's own (unshipped on macOS)
    /// "face-black-digital" asset in the Clock widget. Used by the single City widget.
    case roundedSquare
}

/// Digital proportions, as fractions of the face size D. Chosen by rendering the alternatives
/// (macOS/scripts/render_snapshots.sh → variants-digital.png) — see macOS/docs/DESIGN-SPEC.md.
enum DigitalFaceMetrics {
    /// Rounded-square corner radius.
    static let cornerRadius: CGFloat = 0.25
    /// Seconds ring: gap to the outline, tick length/width (hour ticks are 1.35× longer, 1.5× wider).
    static let ringInset: CGFloat = 0.045
    static let tickLength: CGFloat = 0.055
    static let tickWidth: CGFloat = 0.014
    /// "00:00" in SF Rounded Semibold (monospaced digits) is 2.795 em wide; 0.245 D keeps the widest
    /// time ~0.03 D clear of the 3 and 9 o'clock ticks, so every column uses the same size without shrinking.
    static let timeSize: CGFloat = 0.245
    static let timeWidth: CGFloat = 0.70
    static let periodSize: CGFloat = 0.115
    static let captionSize: CGFloat = 0.10
    static let footnoteSize: CGFloat = 0.085
}

/// Digital counterpart of `AnalogClockFace`: same day/night face colours and the same orange accent, a dial of
/// 60 ticks, and live-updating digits. With seconds on, the line under the time reads ":05 PM" (seconds in
/// orange), or ":05" in 24-hour mode.
struct DigitalClockFace: View {
    let diameter: CGFloat
    let timeZone: TimeZone
    let date: Date
    let isDaytime: Bool
    var twelveHour = true
    var shape: DigitalFaceShape = .circle
    /// Optional caption above the time (city name / abbreviation).
    var caption: String? = nil
    /// Optional footnote below the time ("Today, +0HRS").
    var footnote: String? = nil
    var showsSeconds = true
    var live = false
    var appearance = ClockAppearance()

    var body: some View {
        let D = diameter
        let M = DigitalFaceMetrics.self
        let soft = appearance.softInk(day: isDaytime)
        ZStack {
            faceShape.fill(appearance.faceFill(day: isDaytime))
            // The dial. (A sweeping seconds ring isn't possible: macOS doesn't animate rotations in a
            // third-party widget, ARCHITECTURE §4. The seconds are live text instead.)
            MinuteTickRing(shape: shape, inset: M.ringInset, length: M.tickLength, width: M.tickWidth)
                .fill(soft.opacity(0.55))
                .frame(width: D, height: D)
            VStack(spacing: 0) {
                if let caption {
                    Text(caption)
                        .font(.system(size: M.captionSize * D, weight: .semibold))
                        .foregroundStyle(soft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.bottom, 0.005 * D)
                }
                ClockTimeText(date: date, timeZone: timeZone, twelveHour: twelveHour, live: live)
                    .font(.system(size: M.timeSize * D, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(appearance.ink(day: isDaytime))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if twelveHour || showsSeconds {
                    ClockSubtitleText(date: date, timeZone: timeZone, showsSeconds: showsSeconds,
                                      showsPeriod: twelveHour, live: live,
                                      secondsColor: appearance.accent, periodColor: soft)
                        .font(.system(size: M.periodSize * D, weight: .bold, design: .rounded))
                        .padding(.top, -0.015 * D)
                }
                if let footnote {
                    Text(footnote)
                        .font(.system(size: M.footnoteSize * D, weight: .semibold))
                        .foregroundStyle(soft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .padding(.top, 0.03 * D)
                }
            }
            .frame(width: M.timeWidth * D)
        }
        .frame(width: D, height: D)
    }

    private var faceShape: AnyShape {
        switch shape {
        case .circle: return AnyShape(Circle())
        case .roundedSquare:
            return AnyShape(RoundedRectangle(cornerRadius: DigitalFaceMetrics.cornerRadius * diameter, style: .continuous))
        }
    }
}

/// Live (widget) or static (preview) "1:53" text.
struct ClockTimeText: View {
    let date: Date
    let timeZone: TimeZone
    let twelveHour: Bool
    let live: Bool

    var body: some View {
        let style = ClockText.timeStyle(timeZone: timeZone, twelveHour: twelveHour)
        Group {
            if live {
                Text(.currentDate, format: style)
            } else {
                Text(date, format: style)
            }
        }
        // On the desktop, WidgetKit sizes live date text for its widest possible value and draws it from the
        // leading edge; offline renders don't show this. Centre it explicitly.
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, alignment: .center)
        .inTimeZone(timeZone)
    }
}

/// The line under a digital time: ":05 PM", ":05" (24-hour) or "PM" (seconds off). The seconds are in the
/// accent colour and, in the widget, live text that the system updates every second.
///
/// One `Text`, laid out exactly like `ClockTimeText`. On the desktop, WidgetKit can't size live date text
/// for an unspecified width: an `HStack` with `.fixedSize()` around it hid every digit of the face and drew
/// the seconds at the widget's left edge (macOS 27.2).
struct ClockSubtitleText: View {
    let date: Date
    let timeZone: TimeZone
    let showsSeconds: Bool
    let showsPeriod: Bool
    let live: Bool
    let secondsColor: Color
    let periodColor: Color

    var body: some View {
        line
            .lineLimit(1)
            // Live date text is sized for its widest value and drawn from the leading edge on the desktop:
            // centre it explicitly.
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, alignment: .center)
            .inTimeZone(timeZone)
    }

    private var line: Text {
        let seconds = text(ClockText.secondsStyle(timeZone: timeZone)).monospacedDigit().foregroundStyle(secondsColor)
        let period = text(ClockText.periodStyle(timeZone: timeZone)).foregroundStyle(periodColor)
        switch (showsSeconds, showsPeriod) {
        case (true, true): return Text("\(seconds) \(period)")
        case (true, false): return seconds
        default: return period
        }
    }

    private func text(_ style: Date.VerbatimFormatStyle) -> Text {
        live ? Text(.currentDate, format: style) : Text(date, format: style)
    }
}

extension View {
    /// SwiftUI's `Text(_:format:)` formats with the *environment's* time zone and calendar, ignoring the
    /// ones stored in the format style — without this every digital clock would show local time.
    func inTimeZone(_ timeZone: TimeZone) -> some View {
        environment(\.timeZone, timeZone)
            .environment(\.calendar, ClockMath.calendar(timeZone))
    }
}

/// 60 radial ticks just inside the face outline (circle or rounded square).
struct MinuteTickRing: Shape {
    var shape: DigitalFaceShape
    /// Gap between outline and tick, as a fraction of the diameter.
    var inset: CGFloat
    var length: CGFloat
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        let D = min(rect.width, rect.height)
        let half = D / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for i in 0..<60 {
            let theta = CGFloat(i) * .pi / 30
            let outer = DigitalFaceGeometry.boundaryDistance(shape: shape, theta: theta, half: half) - inset * D
            let isHour = i % 5 == 0
            let len = (isHour ? length * 1.35 : length) * D
            let w = max(0.5, (isHour ? width * 1.5 : width) * D)
            let tick = CGRect(x: -w / 2, y: -outer, width: w, height: len)
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: theta)
            p.addPath(Path(roundedRect: tick, cornerRadius: w / 2), transform: t)
        }
        return p
    }
}

enum DigitalFaceGeometry {
    /// Distance from the centre to the outline along a ray at angle `theta` (radians, clockwise from 12).
    static func boundaryDistance(shape: DigitalFaceShape, theta: CGFloat, half: CGFloat) -> CGFloat {
        switch shape {
        case .circle:
            return half
        case .roundedSquare:
            let rc = DigitalFaceMetrics.cornerRadius * 2 * half
            let a = half - rc
            let dx = abs(sin(theta)), dy = abs(cos(theta))
            if dx > 1e-6 {
                let t = half / dx
                if t * dy <= a + 1e-6 { return t }
            }
            if dy > 1e-6 {
                let t = half / dy
                if t * dx <= a + 1e-6 { return t }
            }
            // Ray hits a corner arc centred at (a, a).
            let b = a * (dx + dy)
            let disc = b * b - (2 * a * a - rc * rc)
            return b + sqrt(max(0, disc))
        }
    }
}
