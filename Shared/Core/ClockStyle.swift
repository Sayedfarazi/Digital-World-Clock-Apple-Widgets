import Foundation

/// Analog (Apple's look) or Digital.
enum ClockStyle: String, Codable, CaseIterable, Sendable {
    case analog
    case digital
}

/// Widget sizes we lay out for. Mirrors WidgetKit's system families without depending on WidgetKit,
/// so the app's previews and the snapshot renderer can use the same layouts.
enum ClockFamily: String, CaseIterable, Sendable {
    case small, medium, large, extraLarge

    /// Nominal macOS widget sizes in points (measured on macOS 27: medium = 344 × 162).
    var nominalSize: CGSize {
        switch self {
        case .small: return CGSize(width: 162, height: 162)
        case .medium: return CGSize(width: 344, height: 162)
        case .large: return CGSize(width: 344, height: 344)
        case .extraLarge: return CGSize(width: 708, height: 344)
        }
    }

    /// How many cities a World Clock widget of this size shows (same as Apple's intent definition:
    /// Small 4, Medium 4, Large 8, Extra Large 12).
    var worldClockCapacity: Int {
        switch self {
        case .small, .medium: return 4
        case .large: return 8
        case .extraLarge: return 12
        }
    }
}
