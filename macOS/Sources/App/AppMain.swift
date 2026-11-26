import AppKit
import SwiftUI
import WidgetKit

/// Host app for the widgets. Two jobs:
///  1. Settings window: the World Clock city list (shared with the widgets) and what a click does. The menu bar
///     has Settings… (⌘,), a Cities menu that acts on the window's list, and Help › Widget Setup.
///  2. Click target: widget clicks open `worldclockwidgets://open[?city=<id>]`. Like Apple's World Clock
///     widget, a click opens the Clock app's World Clock — then this app quits again without a window
///     (and, being an LSUIElement app until its window is shown, without a Dock icon).
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // matches LSUIElement; showWindow() switches to .regular
        app.run()
    }

    /// How long a non-default launch waits for its widget-click URL before showing the window anyway.
    /// The URL normally arrives within a fraction of a second; the margin covers a slow cold launch
    /// (just after login, or under load). Only a non-default launch without a URL ever waits this long.
    private static let launchURLGracePeriod: TimeInterval = 3.0

    private var window: NSWindow?
    private var helpWindow: NSWindow?
    /// The window's list and selection, also used by the Cities menu.
    private let settings = SettingsState()
    /// The app was started by a widget click: it quits again once Clock is open.
    private var launchedForURL = false
    private var finishedLaunching = false
    /// Between a non-default launch and the arrival of its URL. macOS delivers the URL of a cold launch
    /// *after* applicationDidFinishLaunching (verified on macOS 27), so the launch kind decides first.
    private var awaitingLaunchURL = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        finishedLaunching = true
        buildMenu()
        if launchedForURL { return }
        // Finder / Dock / Spotlight / `open` launches are "default" launches; a launch to open a URL is not.
        let isDefaultLaunch = notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool ?? true
        if isDefaultLaunch {
            showWindow()
            return
        }
        awaitingLaunchURL = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchURLGracePeriod) { [weak self] in
            guard let self, self.awaitingLaunchURL else { return }
            self.awaitingLaunchURL = false
            self.showWindow() // not a widget click after all (e.g. restored state)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let click = urls.first(where: { $0.scheme == SharedSettings.urlScheme }) else { return }
        if !finishedLaunching || awaitingLaunchURL {
            launchedForURL = true
            awaitingLaunchURL = false
        }
        handleWidgetClick(click)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWindow() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Widget clicks

    private func handleWidgetClick(_ url: URL) {
        switch SharedSettings.clickAction {
        case .openThisApp:
            showWindow()
        case .openClockApp:
            ClockAppLauncher.openWorldClock { [weak self] opened in
                guard let self else { return }
                if !opened {
                    self.showWindow()
                } else if self.launchedForURL && self.window == nil {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    // MARK: Window

    private func showWindow() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular) // Dock icon + menu bar while the window is open
        }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(state: settings))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Digital World-Clock Widgets"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 780, height: 720))
            window.contentMinSize = NSSize(width: 720, height: 560)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("MainWindow")
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    /// Help › Widget Setup: how to add and edit widgets (it used to be a section of the settings window).
    @objc private func showWidgetSetup(_ sender: Any?) {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        if helpWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: WidgetSetupView()))
            window.title = "Widget Setup"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            helpWindow = window
        }
        NSApp.activate()
        helpWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Menu bar

    @objc private func showSettings(_ sender: Any?) { showWindow() }

    @objc private func addCity(_ sender: Any?) {
        showWindow()
        // The popover needs its button on screen: let a window that was just created lay out first.
        DispatchQueue.main.async { [settings] in settings.addCity() }
    }

    @objc private func removeSelectedCity(_ sender: Any?) { settings.removeSelectedCity() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(removeSelectedCity(_:)) {
            return settings.canRemoveSelection
        }
        return true
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Digital World-Clock Widgets",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Digital World-Clock Widgets", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Digital World-Clock Widgets", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let editItem = NSMenuItem()
        main.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // The same actions and enabled states as the window's Add City… and Remove buttons. No Delete key
        // equivalent: Delete stays with the focused list, so it still deletes characters in a search field.
        let citiesItem = NSMenuItem()
        main.addItem(citiesItem)
        let citiesMenu = NSMenu(title: "Cities")
        citiesMenu.addItem(withTitle: "Add City…", action: #selector(addCity(_:)), keyEquivalent: "").target = self
        citiesMenu.addItem(withTitle: "Remove Selected City", action: #selector(removeSelectedCity(_:)),
                           keyEquivalent: "").target = self
        citiesItem.submenu = citiesMenu

        let windowItem = NSMenuItem()
        main.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        NSApp.windowsMenu = windowMenu

        let helpItem = NSMenuItem()
        main.addItem(helpItem)
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Widget Setup", action: #selector(showWidgetSetup(_:)), keyEquivalent: "").target = self
        helpItem.submenu = helpMenu
        NSApp.helpMenu = helpMenu
        NSApp.mainMenu = main
    }
}

/// Opens Apple's Clock app on its World Clock tab.
enum ClockAppLauncher {
    static let worldClockURL = URL(string: "clock-worldclock:default")!
    static let clockAppURL = URL(fileURLWithPath: "/System/Applications/Clock.app")

    static func openWorldClock(completion: @escaping (Bool) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // Same URL Apple's World Clock widget uses. If the scheme is refused, just launch Clock.
        NSWorkspace.shared.open(worldClockURL, configuration: configuration) { _, error in
            if error == nil {
                DispatchQueue.main.async { completion(true) }
                return
            }
            NSWorkspace.shared.openApplication(at: clockAppURL, configuration: configuration) { _, error in
                DispatchQueue.main.async { completion(error == nil) }
            }
        }
    }
}
