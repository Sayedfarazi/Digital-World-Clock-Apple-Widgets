import SwiftUI

/// Which clock hand a view represents.
enum ClockHandKind {
    case hour, minute, second

    func angle(_ angles: ClockMath.HandAngles) -> Double {
        switch self {
        case .hour: return angles.hour
        case .minute: return angles.minute
        case .second: return angles.second
        }
    }
}

extension View {
    /// Rotates a full-face-sized hand layer (drawn pointing at 12) to the time the angles were computed for.
    ///
    /// Always a static rotation. WidgetKit has a private live clock-hand effect, but on macOS 27.2 it leaves it
    /// out of a third-party widget's archive, so hands using it stay at 12 o'clock (ARCHITECTURE §4). The widget
    /// redraws analog hands from a timeline entry every minute instead (`TimelinePlan.Mode.everyMinute`).
    func clockHand(_ kind: ClockHandKind, angles: ClockMath.HandAngles) -> some View {
        rotationEffect(.degrees(kind.angle(angles)))
    }
}
