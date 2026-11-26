import SwiftUI
import WidgetKit

/// Dial decoration, matching the face assets inside Apple's World Clock widget.
enum DialStyle {
    /// Numerals 1–12, no ticks ("face-noticks-circle"). Used by the World Clock columns.
    case numerals
    /// Numerals plus hour ticks at the rim ("face-ticks-circle"). Used by the large single City clock.
    case numeralsAndTicks
    /// Twelve bars, no numerals ("face-black-nonumerals"). Used when the face is too small for numerals.
    case ticks
}

/// Geometry measured from Apple's widget (macOS/docs/DESIGN-SPEC.md). All values are fractions of the face radius R.
/// Hands/hub/numerals were calibrated against a 2x screenshot of the real widget (R = 71 px).
enum AnalogGeometry {
    static let numeralRadius: CGFloat = 0.82
    static let numeralSize: CGFloat = 0.255
    static let tickedNumeralRadius: CGFloat = 0.72
    static let tickedNumeralSize: CGFloat = 0.233
    static let rimTickCenter: CGFloat = 0.915
    static let majorTick = CGSize(width: 0.021, height: 0.077)
    static let minorTick = CGSize(width: 0.0175, height: 0.070)
    static let barTickInner: CGFloat = 0.695
    static let barTickOuter: CGFloat = 0.935
    static let barTickWidth: CGFloat = 0.056

    static let handBarStart: CGFloat = 0.11
    static let handBarWidth: CGFloat = 0.055
    static let connectorWidth: CGFloat = 0.024
    static let hourHandEnd: CGFloat = 0.55
    static let minuteHandEnd: CGFloat = 0.925
    static let secondHandEnd: CGFloat = 0.97
    static let secondHandTail: CGFloat = 0.16
    static let secondHandWidth: CGFloat = 0.031
    static let hubDiameter: CGFloat = 0.114
    static let accentHubDiameter: CGFloat = 0.071
    static let centerDotDiameter: CGFloat = 0.028
    /// Soft shadow under the hour/minute hands and hub (blur radius; opacity in ClockAppearance.handShadow).
    static let handShadowRadius: CGFloat = 0.025
}

/// Apple-style analog clock face. Hands are separate full-size layers rotated about the centre
/// (`clockHand(_:angles:)`) to the face's `date`.
struct AnalogClockFace: View {
    let diameter: CGFloat
    let timeZone: TimeZone
    let date: Date
    let isDaytime: Bool
    var dial: DialStyle = .numerals
    /// Optional short label inside the dial (the City widget shows the city abbreviation).
    var label: String? = nil
    /// Draw the second hand. Widgets don't: it would stand still (see `ClockOptions.analogSecondHand`).
    var showsSeconds = true
    var appearance = ClockAppearance()

    var body: some View {
        let R = diameter / 2
        let angles = ClockMath.handAngles(at: date, in: timeZone)
        let ink = appearance.ink(day: isDaytime)
        let face = appearance.faceFill(day: isDaytime)
        let shadow = appearance.handShadow
        let shadowRadius = AnalogGeometry.handShadowRadius * R
        ZStack {
            Circle().fill(face)
            DialMarks(dial: dial, radius: R, ink: ink)
            if let label {
                Text(label)
                    .font(.system(size: max(7, 0.135 * R), weight: .semibold))
                    .tracking(0.01 * R)
                    .foregroundStyle(appearance.softInk(day: isDaytime))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(width: 0.8 * R)
                    .position(x: R, y: R + 0.40 * R)
            }

            ClockHandShape(barStart: AnalogGeometry.handBarStart, barEnd: AnalogGeometry.hourHandEnd,
                           barWidth: AnalogGeometry.handBarWidth, connectorWidth: AnalogGeometry.connectorWidth)
                .fill(ink)
                .shadow(color: shadow, radius: shadowRadius)
                .frame(width: diameter, height: diameter)
                .clockHand(.hour, angles: angles)
            ClockHandShape(barStart: AnalogGeometry.handBarStart, barEnd: AnalogGeometry.minuteHandEnd,
                           barWidth: AnalogGeometry.handBarWidth, connectorWidth: AnalogGeometry.connectorWidth)
                .fill(ink)
                .shadow(color: shadow, radius: shadowRadius)
                .frame(width: diameter, height: diameter)
                .clockHand(.minute, angles: angles)
            Circle().fill(ink)
                .frame(width: AnalogGeometry.hubDiameter * R, height: AnalogGeometry.hubDiameter * R)
                .shadow(color: shadow, radius: shadowRadius)

            if showsSeconds {
                Group {
                    SecondHandShape(end: AnalogGeometry.secondHandEnd, tail: AnalogGeometry.secondHandTail,
                                    width: AnalogGeometry.secondHandWidth)
                        .fill(appearance.accent)
                        .frame(width: diameter, height: diameter)
                        .clockHand(.second, angles: angles)
                    Circle().fill(appearance.accent)
                        .frame(width: AnalogGeometry.accentHubDiameter * R, height: AnalogGeometry.accentHubDiameter * R)
                }
                .widgetAccentable()
                Circle().fill(face)
                    .frame(width: AnalogGeometry.centerDotDiameter * R, height: AnalogGeometry.centerDotDiameter * R)
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Numerals and/or tick marks.
struct DialMarks: View {
    let dial: DialStyle
    let radius: CGFloat
    let ink: Color

    var body: some View {
        let R = radius
        ZStack {
            switch dial {
            case .numerals:
                numerals(R: R, at: AnalogGeometry.numeralRadius, size: AnalogGeometry.numeralSize)
            case .numeralsAndTicks:
                numerals(R: R, at: AnalogGeometry.tickedNumeralRadius, size: AnalogGeometry.tickedNumeralSize)
                RimTicks(center: AnalogGeometry.rimTickCenter).fill(ink)
            case .ticks:
                BarTicks().fill(ink)
            }
        }
        .frame(width: 2 * R, height: 2 * R)
    }

    @ViewBuilder
    private func numerals(R: CGFloat, at r: CGFloat, size: CGFloat) -> some View {
        ForEach(1...12, id: \.self) { n in
            let theta = Double(n) * .pi / 6
            Text(verbatim: "\(n)")
                .font(.system(size: size * R, weight: .semibold))
                .foregroundStyle(ink)
                .fixedSize()
                .position(x: R + r * R * CGFloat(sin(theta)), y: R - r * R * CGFloat(cos(theta)))
        }
    }
}

/// 12 hour ticks at the rim; 3/6/9/12 slightly longer and wider.
struct RimTicks: Shape {
    var center: CGFloat
    func path(in rect: CGRect) -> Path {
        let R = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        for i in 0..<12 {
            let size = i % 3 == 0 ? AnalogGeometry.majorTick : AnalogGeometry.minorTick
            let tick = CGRect(x: -size.width * R / 2, y: -(center + size.height / 2) * R,
                              width: size.width * R, height: size.height * R)
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(i) * .pi / 6)
            p.addPath(Path(tick), transform: t)
        }
        return p
    }
}

/// 12 rounded bars used on small faces instead of numerals.
struct BarTicks: Shape {
    func path(in rect: CGRect) -> Path {
        let R = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = AnalogGeometry.barTickWidth * R
        let bar = CGRect(x: -w / 2, y: -AnalogGeometry.barTickOuter * R, width: w,
                         height: (AnalogGeometry.barTickOuter - AnalogGeometry.barTickInner) * R)
        var p = Path()
        for i in 0..<12 {
            let t = CGAffineTransform(translationX: c.x, y: c.y).rotated(by: CGFloat(i) * .pi / 6)
            p.addPath(Path(roundedRect: bar, cornerRadius: w / 2), transform: t)
        }
        return p
    }
}

/// Hour / minute hand pointing at 12: a thin connector from the hub, then a rounded bar.
struct ClockHandShape: Shape {
    var barStart: CGFloat
    var barEnd: CGFloat
    var barWidth: CGFloat
    var connectorWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let R = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        var p = Path()
        let cw = max(0.5, connectorWidth * R)
        p.addRect(CGRect(x: c.x - cw / 2, y: c.y - (barStart + barWidth / 2) * R, width: cw,
                         height: (barStart + barWidth / 2) * R))
        let bw = max(1, barWidth * R)
        p.addRoundedRect(in: CGRect(x: c.x - bw / 2, y: c.y - barEnd * R, width: bw, height: (barEnd - barStart) * R),
                         cornerSize: CGSize(width: bw / 2, height: bw / 2))
        return p
    }
}

/// Thin second hand with a short tail behind the hub.
struct SecondHandShape: Shape {
    var end: CGFloat
    var tail: CGFloat
    var width: CGFloat

    func path(in rect: CGRect) -> Path {
        let R = min(rect.width, rect.height) / 2
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let w = max(0.6, width * R)
        return Path(roundedRect: CGRect(x: c.x - w / 2, y: c.y - end * R, width: w, height: (end + tail) * R),
                    cornerRadius: w / 2)
    }
}
