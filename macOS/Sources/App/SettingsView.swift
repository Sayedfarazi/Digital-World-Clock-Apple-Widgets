import AppKit
import Observation
import SwiftUI
import WidgetKit

/// The settings window's state. The menu bar (AppMain.swift) shares it: Cities › Add City… and Remove Selected
/// City call the same functions, with the same enabled states, as the window's buttons.
@Observable
final class SettingsState {
    let model = CityListModel()
    /// The selected row of the World Clock city list.
    var selection: City.ID?
    /// The Add City search popover is open.
    var showingAddCity = false

    var selectedCity: City? { selection.flatMap { id in model.cities.first { $0.id == id } } }
    /// A city is selected, and it isn't the last one (the list keeps at least one: CityListModel.canRemove).
    var canRemoveSelection: Bool { selectedCity != nil && model.canRemove }

    func addCity() { showingAddCity = true }

    func removeSelectedCity() {
        guard canRemoveSelection, let city = selectedCity else { return }
        model.remove(city)
        selection = nil
    }
}

/// The app's window. It opens on the World Clock city list; one live preview sits below it. How to add and edit
/// widgets is in Help › Widget Setup (WidgetSetupView).
struct SettingsView: View {
    let state: SettingsState
    /// Changes only the preview, never a widget (widgets get their style from Edit Widget).
    @ViewState private var previewStyle = ClockStyle.analog
    @ViewState private var choosingCityWidgetCity = false

    var body: some View {
        let model = state.model
        Form {
            Section {
                List(selection: Bindable(state).selection) {
                    ForEach(model.cities) { city in
                        CityRow(city: city)
                            .tag(city.id)
                            .contextMenu {
                                Button("Remove \(city.name)") { model.remove(city) }
                                    .disabled(!model.canRemove)
                            }
                    }
                    .onMove { model.move(from: $0, to: $1) }
                    .onDelete { model.remove(at: $0) }
                }
                .frame(minHeight: 180)
                // Delete removes a city only while the list has focus, so it still deletes characters in a search
                // field. (The menu's Remove Selected City has no key equivalent for the same reason.)
                .onDeleteCommand { state.removeSelectedCity() }
                .accessibilityLabel("World Clock Cities")
                HStack {
                    Button {
                        state.removeSelectedCity()
                    } label: {
                        Label("Remove", systemImage: "minus")
                    }
                    .disabled(!state.canRemoveSelection)
                    Spacer()
                    Button("Restore Default Cities") { model.resetToDefault() }
                        .disabled(!model.isCustomized)
                }
            } header: {
                HStack {
                    Text("World Clock Cities")
                    Spacer()
                    Button {
                        state.addCity()
                    } label: {
                        Label("Add City…", systemImage: "plus")
                    }
                    .font(.body)
                    .popover(isPresented: Bindable(state).showingAddCity, arrowEdge: .bottom) {
                        CitySearchView(added: Set(model.cities.map(\.id))) { city in
                            model.add(city)
                            state.showingAddCity = false
                        }
                    }
                }
            } footer: {
                Text("Drag cities to reorder.")
            }

            Section {
                PreviewWidget(cities: model.cities, style: previewStyle)
                    .frame(maxWidth: .infinity)
            } header: {
                HStack {
                    Text("Preview")
                    Spacer()
                    Picker("Preview style", selection: $previewStyle) {
                        Text("Analog").tag(ClockStyle.analog)
                        Text("Digital").tag(ClockStyle.digital)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .font(.body)
                    .accessibilityLabel("Preview style")
                }
            }

            Section("City Widget") {
                let automatic = model.cityWidgetCity == nil
                let city = model.cityWidgetCity ?? CityDatabase.shared.localCity
                LabeledContent {
                    HStack(spacing: 12) {
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(city.name)
                                .foregroundStyle(.primary)
                            Text(automatic ? "From this Mac’s time zone" : city.country)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        if !automatic {
                            Button("Use Mac’s Time Zone") { model.cityWidgetCity = nil }
                        }
                        Button("Choose City…") { choosingCityWidgetCity = true }
                            .popover(isPresented: $choosingCityWidgetCity, arrowEdge: .bottom) {
                                CitySearchView { picked in
                                    model.cityWidgetCity = picked
                                    choosingCityWidgetCity = false
                                }
                            }
                    }
                } label: {
                    Text("Default city")
                }
            }

            Section {
                Picker("Widget clicks open", selection: Bindable(model).clickAction) {
                    ForEach(SharedSettings.ClickAction.allCases, id: \.self) { action in
                        Text(action.title).tag(action)
                    }
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
    }
}

/// One live medium World Clock widget of the list's first four cities, in the style the segmented control picks.
private struct PreviewWidget: View {
    let cities: [City]
    let style: ClockStyle

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let clocks = CityClock.list(Array(cities.prefix(4)), date: context.date)
            WorldClockLayout(family: .medium, clocks: clocks, options: ClockOptions(style: style),
                             size: ClockFamily.medium.nominalSize)
                .background(ClockPalette.widgetBackground,
                            in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .environment(\.colorScheme, .dark)
        }
        .padding(.vertical, 6)
    }
}

private struct CityRow: View {
    let city: City

    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(city.name).font(.body.weight(.medium))
                    if !city.country.isEmpty {
                        Text(city.country).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                let clock = CityClock(city: city, date: context.date)
                Text("\(clock.dayLabel), \(clock.offsetLabel)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(context.date, format: Date.FormatStyle(date: .omitted, time: .shortened))
                    .inTimeZone(city.timeZone)
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 70, alignment: .trailing)
            }
            .padding(.vertical, 2)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Search box over Apple's 582 Clock cities. Return picks the first result; Escape closes it.
private struct CitySearchView: View {
    /// Cities already in the list (Add City): marked "Added" and not picked again. Empty for the City widget's
    /// picker, which replaces its one city.
    var added: Set<City.ID> = []
    let onPick: (City) -> Void
    @ViewState private var query = ""
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 8) {
            TextField("Search cities or countries", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    guard let first = results.first else { return }
                    if added.contains(first.id) {
                        NSSound.beep()
                    } else {
                        onPick(first)
                    }
                }
            List(results) { city in
                let isAdded = added.contains(city.id)
                Button {
                    onPick(city)
                } label: {
                    HStack {
                        Text(city.name)
                        Spacer()
                        if isAdded {
                            Label("Added", systemImage: "checkmark")
                                .foregroundStyle(.secondary)
                        } else {
                            Text(city.country).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isAdded)
                .accessibilityLabel(isAdded ? "\(city.name), \(city.country), already added" : "\(city.name), \(city.country)")
            }
            .listStyle(.plain)
        }
        .padding(12)
        .frame(width: 360, height: 380)
        .onAppear { focused = true }
        .onExitCommand { dismiss() }
    }

    /// Every match (a country can have more than 100 cities; the list is lazy).
    private var results: [City] { CityDatabase.shared.search(query) }
}

/// Help › Widget Setup: how to add a widget, change one, and how its cities are chosen.
struct WidgetSetupView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("**Add a widget.** Right-click the desktop and choose **Edit Widgets…** (or open Notification Center and click **Edit Widgets**). Then search for **Digital World-Clock Widgets**.")
            Text("**Change one widget.** Right-click the widget and choose Edit with its name, such as **Edit “World\u{00A0}Clock”**. **Style** switches between Analog and Digital. On digital clocks, **Time Format** sets 12-hour or 24-hour time (System Setting follows this Mac), and **Show Seconds** shows the seconds.")
            Text("**Choose cities.** Cities picked in a widget appear first. The app’s list fills the remaining places, in order. Small and medium widgets hold four cities, large holds eight, and extra large holds twelve. A City widget shows the app’s default city unless you pick one for it.")
            Text("**No second hand.** macOS doesn’t let other apps’ widgets animate clock hands, so analog hands move once a minute. Digital clocks can show the seconds.")
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .padding(20)
        .frame(width: 460)
    }
}
