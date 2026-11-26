import AppIntents
import os
import SwiftUI
import WidgetKit

// MARK: - Bundle

@main
struct ClockWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WorldClockWidget()
        WorldClockDigitalWidget()
        CityWidget()
        CityDigitalWidget()
    }
}

/// Widget kinds. Changing one orphans widgets already on users' desktops.
enum ClockWidgetKind {
    static let worldClock = "WorldClock"
    static let worldClockDigital = "WorldClockDigital"
    static let city = "City"
    static let cityDigital = "CityDigital"
}

struct WorldClockWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ClockWidgetKind.worldClock, intent: WorldClockAnalogIntent.self,
                               provider: ClockProvider<WorldClockAnalogIntent>(isWorldClock: true)) { entry in
            ClockWidgetView(entry: entry)
        }
        .configurationDisplayName("World Clock")
        .description("View the time in multiple cities around the world.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct WorldClockDigitalWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ClockWidgetKind.worldClockDigital, intent: WorldClockDigitalIntent.self,
                               provider: ClockProvider<WorldClockDigitalIntent>(isWorldClock: true)) { entry in
            ClockWidgetView(entry: entry)
        }
        .configurationDisplayName("World Clock Digital")
        .description("View the time in multiple cities around the world, as digital clocks.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
        .contentMarginsDisabled()
    }
}

struct CityWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ClockWidgetKind.city, intent: CityAnalogIntent.self,
                               provider: ClockProvider<CityAnalogIntent>(isWorldClock: false)) { entry in
            ClockWidgetView(entry: entry)
        }
        .configurationDisplayName("City")
        .description("Check the time in a city of your choice.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

struct CityDigitalWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: ClockWidgetKind.cityDigital, intent: CityDigitalIntent.self,
                               provider: ClockProvider<CityDigitalIntent>(isWorldClock: false)) { entry in
            ClockWidgetView(entry: entry)
        }
        .configurationDisplayName("City Digital")
        .description("Check the time in a city of your choice, as a digital clock.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}

// MARK: - Timeline

struct ClockEntry: TimelineEntry {
    let date: Date
    let cities: [City]
    let options: ClockOptions
    let isWorldClock: Bool
}

struct ClockProvider<Intent: ClockConfigurationIntent>: AppIntentTimelineProvider {
    let isWorldClock: Bool

    func placeholder(in context: Context) -> ClockEntry {
        ClockTimelineBuilder.entry(for: Intent(), isWorldClock: isWorldClock, family: context.family,
                                   date: Date(), live: false)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> ClockEntry {
        ClockTimelineBuilder.entry(for: configuration, isWorldClock: isWorldClock, family: context.family,
                                   date: Date(), live: true)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<ClockEntry> {
        ClockTimelineBuilder.timeline(for: configuration, isWorldClock: isWorldClock, family: context.family,
                                      now: Date())
    }
}

enum ClockTimelineBuilder {
    private static let log = Logger(subsystem: "com.worldclockwidgets.app.ClockWidgets", category: "timeline")

    static func timeline<Intent: ClockConfigurationIntent>(for intent: Intent, isWorldClock: Bool,
                                                           family: WidgetFamily, now: Date) -> Timeline<ClockEntry> {
        let cities = resolveCities(for: intent, isWorldClock: isWorldClock, family: family)
        // Digital: live text, entries only where a face colour or label changes. Analog: the hands are drawn
        // from the entry's date (macOS won't animate them), so an entry every minute.
        let mode: TimelinePlan.Mode = intent.clockStyle == .analog ? .everyMinute : .liveText
        let plan = TimelinePlan.make(now: now, cities: cities, local: .autoupdatingCurrent, mode: mode)
        // One line per timeline (a few a day): what Edit Widget delivered and what the widget made of it.
        // log show --last 1h --predicate 'subsystem == "com.worldclockwidgets.app.ClockWidgets"'
        let summary = "\(Intent.self) \(family): style \(intent.styleValue) -> \(intent.clockStyle.rawValue), "
            + "time format \(intent.timeFormatValue) -> \(intent.hourCycle.rawValue), "
            + "seconds \(intent.showsSecondsValue), picked \(intent.cityValues) -> \(cities.map(\.name)), "
            + "\(plan.dates.count) entries (\(mode.rawValue)) until \(plan.dates.last ?? now)"
        log.notice("\(summary, privacy: .public)")
        return Timeline(entries: plan.dates.map { entry(for: intent, cities: cities, isWorldClock: isWorldClock, date: $0, live: true) },
                        policy: .atEnd)
    }

    static func entry<Intent: ClockConfigurationIntent>(for intent: Intent, isWorldClock: Bool, family: WidgetFamily,
                                                        date: Date, live: Bool) -> ClockEntry {
        entry(for: intent, cities: resolveCities(for: intent, isWorldClock: isWorldClock, family: family),
              isWorldClock: isWorldClock, date: date, live: live)
    }

    static func entry<Intent: ClockConfigurationIntent>(for intent: Intent, cities: [City], isWorldClock: Bool,
                                                        date: Date, live: Bool) -> ClockEntry {
        var options = ClockOptions(style: intent.clockStyle, showsSeconds: intent.showsSecondsValue,
                                   hourCycle: intent.hourCycle)
        options.live = live
        // Static seconds (a placeholder) would be wrong most of the time: show them only as live text.
        if !live { options.showsSeconds = false }
        return ClockEntry(date: date, cities: cities, options: options, isWorldClock: isWorldClock)
    }

    /// City widget: the chosen city, else the app's "City Widget" city, else the device's city.
    /// World Clock: the cities picked in Edit Widget's rows, then, for the rows left empty, the app's list, else
    /// the default list (padded to fill the size).
    static func resolveCities<Intent: ClockConfigurationIntent>(for intent: Intent, isWorldClock: Bool,
                                                                family: WidgetFamily) -> [City] {
        let database = CityDatabase.shared
        let chosen = intent.chosenCities
        guard isWorldClock else {
            let appDefault = SharedSettings.cityWidgetCityID.flatMap { database.city(id: $0) }
            return [chosen.first ?? appDefault ?? database.localCity]
        }
        let capacity = ClockFamily(family).worldClockCapacity
        var list = SharedSettings.storedCityIDs()?.compactMap { database.city(id: $0) } ?? []
        if list.isEmpty {
            list = DefaultCities.filled(DefaultCities.seedList(database: database), to: capacity, database: database)
        }
        return DefaultCities.slots(picked: chosen, list: list, capacity: capacity)
    }
}

extension ClockFamily {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemSmall: self = .small
        case .systemLarge: self = .large
        case .systemExtraLarge: self = .extraLarge
        default: self = .medium
        }
    }
}

// MARK: - View

struct ClockWidgetView: View {
    let entry: ClockEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        var options = entry.options
        options.appearance.monochrome = renderingMode != .fullColor
        let clocks = CityClock.list(entry.cities, date: entry.date)
        return GeometryReader { geometry in
            if entry.isWorldClock {
                WorldClockLayout(family: ClockFamily(family), clocks: clocks, options: options, size: geometry.size)
            } else if let clock = clocks.first {
                CityLayout(clock: clock, options: options, size: geometry.size)
            }
        }
        .containerBackground(for: .widget) {
            ClockPalette.widgetBackground
        }
        .widgetURL(openURL)
    }

    /// Clicks go to the host app. On macOS it opens Apple's Clock app (or itself; see SharedSettings.clickAction);
    /// on iOS a tap opens the app.
    private var openURL: URL? {
        var components = URLComponents()
        components.scheme = SharedSettings.urlScheme
        components.host = "open"
        if !entry.isWorldClock, let city = entry.cities.first {
            components.queryItems = [URLQueryItem(name: "city", value: city.id)]
        }
        return components.url
    }
}
