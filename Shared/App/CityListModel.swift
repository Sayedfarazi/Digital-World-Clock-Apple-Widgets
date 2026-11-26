import Observation
import SwiftUI
import WidgetKit

/// SwiftUI's `@State` is a macro in the macOS 27 SDK, and its plugin (SwiftUIMacros) ships only with Xcode. The
/// macOS app builds with the Command Line Tools, so code shared with it (and the iOS app, which is also
/// type-checked with the Command Line Tools: iOS/README.md) uses the property wrapper directly.
typealias ViewState<Value> = SwiftUI.State<Value>

/// The app's World Clock list (what "World Clock" widgets show when no cities are picked in Edit Widget) and
/// the City widget's city. Used by the macOS settings window and the iOS app.
@Observable
final class CityListModel {
    private(set) var cities: [City]
    /// True once the user edited the list (until then the default list is used, padded for large sizes).
    private(set) var isCustomized: Bool
    /// macOS only: what a click on a widget does (on iOS a tap always opens the app).
    var clickAction: SharedSettings.ClickAction {
        didSet {
            SharedSettings.clickAction = clickAction
        }
    }
    /// What "City" widgets show when no city is picked in Edit Widget (nil = this device's city).
    var cityWidgetCity: City? {
        didSet {
            SharedSettings.cityWidgetCityID = cityWidgetCity?.id
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private let database = CityDatabase.shared

    init() {
        cities = DefaultCities.worldClockList(database: database)
        isCustomized = SharedSettings.storedCityIDs() != nil
        clickAction = SharedSettings.clickAction
        cityWidgetCity = SharedSettings.cityWidgetCityID.flatMap { CityDatabase.shared.city(id: $0) }
    }

    func add(_ city: City) {
        guard !cities.contains(where: { $0.id == city.id }) else { return }
        cities.append(city)
        save()
    }

    /// The list keeps at least one city: an empty saved list means "use the default list", so the
    /// widgets would show different cities from the app. Every remove path (button, Delete key,
    /// context menu, swipe) goes through these two functions.
    var canRemove: Bool { cities.count > 1 }

    func remove(at offsets: IndexSet) {
        guard cities.count - offsets.count >= 1 else { return }
        cities.remove(atOffsets: offsets)
        save()
    }

    func remove(_ city: City) {
        guard canRemove, cities.contains(where: { $0.id == city.id }) else { return }
        cities.removeAll { $0.id == city.id }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        cities.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func resetToDefault() {
        SharedSettings.store.removeObject(forKey: SharedSettings.cityIDsKey)
        cities = DefaultCities.seedList(database: database)
        isCustomized = false
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func save() {
        SharedSettings.setCityIDs(cities.map(\.id))
        isCustomized = true
        WidgetCenter.shared.reloadAllTimelines()
    }
}
