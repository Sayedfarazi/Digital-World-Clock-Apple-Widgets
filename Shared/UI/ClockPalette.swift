import SwiftUI

/// Colours taken from Apple's World Clock widget (Assets.car of Clock.app/PlugIns/WorldClockWidget.appex)
/// and measured from a macOS 27 screenshot (macOS/docs/reference/apple-world-clock-medium-dark.png).
enum ClockPalette {
    /// "WidgetBackgroundColor" — the built-in widget is dark in both Light and Dark appearance.
    static let widgetBackground = Color(.displayP3, red: 0.110, green: 0.110, blue: 0.118)
    /// The orange second hand. Apple's widget draws it in system orange (screenshot: 255,149,0 in Light
    /// appearance), not its "WidgetAccentColor" asset (that asset only tints the widget's edit UI).
    static let accent = Color.orange
    static let dayFace = Color.white
    /// Night face, sampled from the screenshot (57,57,59).
    static let nightFace = Color(.sRGB, red: 57 / 255, green: 57 / 255, blue: 59 / 255)
    /// Numerals and hands on the white face are the widget background colour, not pure black (28,28,30).
    static let dayInk = widgetBackground
    /// Numerals and hands on the night face are an off-white (245,245,248).
    static let nightInk = Color(.sRGB, red: 245 / 255, green: 245 / 255, blue: 248 / 255)
    /// Day/offset labels ("Today", "+3HRS") — systemGray #8E8E93.
    static let secondaryLabel = Color(.sRGB, red: 142 / 255, green: 142 / 255, blue: 147 / 255)
    static let primaryLabel = Color.white
}

/// How the clock should be painted. `monochrome` is used when WidgetKit renders the widget in the
/// vibrant (desktop, unfocused) or accented (tinted) modes, where colours are replaced by luminance.
struct ClockAppearance: Equatable {
    var monochrome = false

    func faceFill(day: Bool) -> Color {
        monochrome ? Color.white.opacity(day ? 0.24 : 0.10) : (day ? ClockPalette.dayFace : ClockPalette.nightFace)
    }

    func ink(day: Bool) -> Color {
        monochrome ? .white : (day ? ClockPalette.dayInk : ClockPalette.nightInk)
    }

    /// Secondary ink inside faces (AM/PM on digital faces, tick marks).
    func softInk(day: Bool) -> Color {
        monochrome ? Color.white.opacity(0.65) : (day ? Color.black.opacity(0.45) : Color.white.opacity(0.55))
    }

    var accent: Color { monochrome ? .white : ClockPalette.accent }
    /// Soft shadow under the hour/minute hands (fitted to the screenshot's edge profile). None in monochrome modes.
    var handShadow: Color { monochrome ? .clear : Color.black.opacity(0.30) }
    var primaryLabel: Color { ClockPalette.primaryLabel }
    var secondaryLabel: Color { monochrome ? Color.white.opacity(0.6) : ClockPalette.secondaryLabel }
}
