import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Renders the widget layouts to PNG files without installing anything (macOS/scripts/render_snapshots.sh),
// and the app icon (macOS/scripts/build.sh).
//
//   Snapshot <output-dir> <path-to-cities.json>          gallery of every kind × size × style
//   Snapshot --icon <AppIcon.iconset> <cities.json>      app icon PNGs for iconutil
//   Snapshot --ios-icon <output-dir> <cities.json>       iOS app icon: AppIcon.png, 1024 × 1024, no alpha channel
//                                                        (iOS/App/Assets.xcassets/AppIcon.appiconset)
//   Snapshot --readme <output-dir> <cities.json>         README images (docs/images): widgets on a desktop backdrop
//
// Every PNG it writes is listed, one name per line, in <output-dir>/manifest.txt. It exits non-zero (and says
// why on stderr) if the output directory can't be made or any image can't be rendered or written.

var args = CommandLine.arguments
let iconMode = args.count >= 2 && args[1] == "--icon"
let iosIconMode = args.count >= 2 && args[1] == "--ios-icon"
let readmeMode = args.count >= 2 && args[1] == "--readme"
if iconMode || iosIconMode || readmeMode { args.remove(at: 1) }
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: Snapshot [--icon | --ios-icon | --readme] <output-dir> <cities.json>\n".data(using: .utf8)!)
    exit(2)
}
let outputDir = URL(fileURLWithPath: args[1], isDirectory: true)
let database: CityDatabase
do {
    database = try CityDatabase(contentsOf: URL(fileURLWithPath: args[2]))
} catch {
    FileHandle.standardError.write("cannot load cities: \(error)\n".data(using: .utf8)!)
    exit(1)
}
do {
    try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
} catch {
    FileHandle.standardError.write("cannot create \(outputDir.path): \(error.localizedDescription)\n".data(using: .utf8)!)
    exit(1)
}

/// Files written, and renders that failed (reported on stderr; the tool then exits 1).
var written: [String] = []
var failures: [String] = []

func fail(_ message: String) {
    failures.append(message)
    FileHandle.standardError.write("error: \(message)\n".data(using: .utf8)!)
}

/// Corner radius of a macOS desktop widget (only used to make snapshots look like the real thing).
let widgetCornerRadius: CGFloat = 23

/// The widget as WidgetKit would show it: content on the dark container background.
struct WidgetFrame<Content: View>: View {
    let size: CGSize
    let monochrome: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(width: size.width, height: size.height)
            .background(
                RoundedRectangle(cornerRadius: widgetCornerRadius, style: .continuous)
                    .fill(monochrome ? Color(white: 0.30) : ClockPalette.widgetBackground)
            )
            .clipShape(RoundedRectangle(cornerRadius: widgetCornerRadius, style: .continuous))
            .padding(12)
            .background(Color(white: monochrome ? 0.55 : 0.80))
            .environment(\.colorScheme, .dark)
    }
}

@MainActor
func write<V: View>(_ view: V, _ name: String, scale: CGFloat = 2, opaque: Bool = false) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = scale
    let url = outputDir.appendingPathComponent(name + ".png")
    guard var image = renderer.cgImage else { return fail("could not render \(name)") }
    if opaque {
        // The App Store refuses an app icon with an alpha channel, even a fully opaque one: redraw without one.
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return fail("could not flatten \(name)")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let flat = context.makeImage() else { return fail("could not flatten \(name)") }
        image = flat
    }
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        return fail("could not create \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return fail("could not write \(url.path)") }
    written.append(url.lastPathComponent)
    print("wrote \(url.path)")
}

func city(_ id: String) -> City { database.city(id: id)! }

// Same moment as macOS/docs/reference/apple-world-clock-medium-dark.png
// (Saturday 21 Nov 2026, 1:53:27 PM in New York).
let newYork = TimeZone(identifier: "America/New_York")!
var refComponents = DateComponents(year: 2026, month: 11, day: 21, hour: 13, minute: 53, second: 27)
refComponents.timeZone = newYork
let referenceDate = ClockMath.calendar(newYork).date(from: refComponents)!
/// The cities in that screenshot, for the calibration render only (compared with it pixel by pixel).
let calibrationCities = ["199", "152", "137", "37"].map(city)
/// Every other render shows the app's default list on a Mac in New York's zone:
/// New York, Los Angeles, Dhaka, Berlin; filled with well-known cities for the larger sizes.
let defaultCities = DefaultCities.seedList(database: database, local: city("199"))
let moreCities = DefaultCities.filled(defaultCities, to: 12, database: database)

@MainActor
func renderAll() {
    for style in ClockStyle.allCases {
        for mono in [false, true] {
            var options = ClockOptions(style: style, showsSeconds: true, hourCycle: .twelveHour)
            options.appearance.monochrome = mono
            let suffix = "\(style.rawValue)\(mono ? "-mono" : "")"

            // World Clock, every size.
            for family in ClockFamily.allCases {
                let size = family.nominalSize
                let clocks = CityClock.list(Array(moreCities.prefix(family.worldClockCapacity)),
                                            date: referenceDate, local: newYork)
                write(WidgetFrame(size: size, monochrome: mono) {
                    WorldClockLayout(family: family, clocks: clocks, options: options, size: size)
                }, "worldclock-\(family.rawValue)-\(suffix)")
            }

            // City, day and night.
            for (cityID, tag) in [("199", "day"), ("78", "night")] {
                let size = ClockFamily.small.nominalSize
                let clock = CityClock(city: city(cityID), date: referenceDate, local: newYork)
                write(WidgetFrame(size: size, monochrome: mono) {
                    CityLayout(clock: clock, options: options, size: size)
                }, "city-\(tag)-\(suffix)")
            }
        }
    }

    // 24-hour digital, with seconds (":27" under the time) and without (no line under the time at all).
    var options24 = ClockOptions(style: .digital, showsSeconds: true, hourCycle: .twentyFourHour)
    let size = ClockFamily.medium.nominalSize
    write(WidgetFrame(size: size, monochrome: false) {
        WorldClockLayout(family: .medium, clocks: CityClock.list(defaultCities, date: referenceDate, local: newYork),
                         options: options24, size: size)
    }, "worldclock-medium-digital-24h")
    options24.showsSeconds = false
    write(WidgetFrame(size: size, monochrome: false) {
        WorldClockLayout(family: .medium, clocks: CityClock.list(defaultCities, date: referenceDate, local: newYork),
                         options: options24, size: size)
    }, "worldclock-medium-digital-24h-noseconds")

    // Exact comparison image for the reference screenshot (no frame, 2x). Apple's widget has a second hand;
    // ours can't animate one, so the widget leaves it out, but this calibration render draws it.
    var calibration = ClockOptions(style: .analog)
    calibration.analogSecondHand = true
    let compare = WorldClockLayout(family: .medium,
                                   clocks: CityClock.list(calibrationCities, date: referenceDate, local: newYork),
                                   options: calibration, size: size)
        // macOS 27 draws desktop widgets on a glass material; the screenshot's background runs from
        // (55,55,57) at the top to (39,39,41) at the bottom. Mimic it so the diff shows only real differences.
        .background(LinearGradient(colors: [Color(.sRGB, red: 55 / 255, green: 55 / 255, blue: 57 / 255),
                                            Color(.sRGB, red: 39 / 255, green: 39 / 255, blue: 41 / 255)],
                                   startPoint: .top, endPoint: .bottom))
    write(compare, "compare-medium-analog")
}

/// Contact sheet of the final digital design: 12h / 24h / no seconds, day and night.
@MainActor
func renderDigitalSheet() {
    let medium = ClockFamily.medium.nominalSize
    let small = ClockFamily.small.nominalSize
    let clocks = CityClock.list(defaultCities, date: referenceDate, local: newYork)
    let configs: [(HourCycle, Bool, String)] = [(.twelveHour, true, "12h"), (.twentyFourHour, true, "24h"),
                                                 (.twelveHour, false, "no seconds")]
    let view = VStack(alignment: .leading, spacing: 0) {
        ForEach(configs.indices, id: \.self) { i in
            let c = configs[i]
            let options = ClockOptions(style: .digital, showsSeconds: c.1, hourCycle: c.0)
            HStack(spacing: 0) {
                WidgetFrame(size: medium, monochrome: false) {
                    WorldClockLayout(family: .medium, clocks: clocks, options: options, size: medium)
                }
                WidgetFrame(size: small, monochrome: false) {
                    CityLayout(clock: clocks[0], options: options, size: small)
                }
                WidgetFrame(size: small, monochrome: false) {
                    CityLayout(clock: clocks[2], options: options, size: small)
                }
                WidgetFrame(size: small, monochrome: false) {
                    WorldClockLayout(family: .small, clocks: clocks, options: options, size: small)
                }
                Text(c.2).font(.system(size: 14, weight: .bold)).padding(8).frame(width: 110)
            }
        }
    }
    .background(Color(white: 0.8))
    write(view, "sheet-digital")
}

/// The app icon shows the same time on a light 24-hour face and a dark 12-hour face.
struct AppIconFaces: View {
    let diameter: CGFloat
    let spacing: CGFloat

    static let background = LinearGradient(colors: [Color(white: 0.25), Color(white: 0.10)],
                                           startPoint: .top, endPoint: .bottom)

    var body: some View {
        let utc = TimeZone(identifier: "UTC")!
        let components = DateComponents(timeZone: utc, year: 2026, month: 1, day: 1, hour: 22, minute: 9)
        let time = ClockMath.calendar(utc).date(from: components)!
        return HStack(spacing: spacing) {
            DigitalClockFace(diameter: diameter, timeZone: utc, date: time, isDaytime: true,
                             twelveHour: false, showsSeconds: false)
            DigitalClockFace(diameter: diameter, timeZone: utc, date: time, isDaytime: false,
                             twelveHour: true, showsSeconds: false)
        }
    }
}

/// macOS app icon: the artwork on the widget's dark squircle (macOS icon grid: 824 pt body inside a 1024 pt
/// canvas).
struct AppIconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(AppIconFaces.background)
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 12, y: 8)
            AppIconFaces(diameter: 340, spacing: 34)
        }
        .frame(width: 1024, height: 1024)
        .environment(\.colorScheme, .dark)
    }
}

/// iOS app icon: the artwork on a full square, which iOS masks to its own rounded shape.
struct IOSAppIconView: View {
    var body: some View {
        AppIconFaces(diameter: 400, spacing: 40)
            .frame(width: 1024, height: 1024)
            .background(AppIconFaces.background)
            .environment(\.colorScheme, .dark)
    }
}

@MainActor
func renderIcon() {
    let sizes: [(String, CGFloat)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024),
    ]
    for (name, px) in sizes {
        write(AppIconView(), name, scale: px / 1024)
    }
}

@MainActor
func renderIOSIcon() {
    write(IOSAppIconView(), "AppIcon", scale: 1, opaque: true)
}

// MARK: README images (macOS/scripts/render_snapshots.sh --readme → docs/images)

/// A made-up desktop wallpaper behind the README's widgets.
struct Backdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.20, green: 0.33, blue: 0.75), Color(red: 0.47, green: 0.30, blue: 0.78)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.98, green: 0.60, blue: 0.50).opacity(0.85), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 650)
            RadialGradient(colors: [Color(red: 0.35, green: 0.78, blue: 0.92).opacity(0.7), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 550)
        }
    }
}

/// A widget as it sits on the desktop: the widget's dark background, a faint rim and a soft shadow.
struct DesktopWidget<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: () -> Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: widgetCornerRadius, style: .continuous)
        content()
            .frame(width: size.width, height: size.height)
            .background(shape.fill(ClockPalette.widgetBackground))
            .clipShape(shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .compositingGroup()
            .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
            .environment(\.colorScheme, .dark)
    }
}

/// One README image: the content on the backdrop, with rounded corners.
struct ReadmeImage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(36)
            .background(Backdrop())
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

let readmeAnalog = ClockOptions(style: .analog, showsSeconds: true, hourCycle: .twelveHour)
let readmeDigital = ClockOptions(style: .digital, showsSeconds: true, hourCycle: .twelveHour)
let readmeGap: CGFloat = 20

/// A World Clock widget of `family`, showing the default cities.
@MainActor
func readmeWorldClock(_ family: ClockFamily, _ options: ClockOptions) -> some View {
    let size = family.nominalSize
    let clocks = CityClock.list(Array(moreCities.prefix(family.worldClockCapacity)), date: referenceDate, local: newYork)
    return DesktopWidget(size: size) {
        WorldClockLayout(family: family, clocks: clocks, options: options, size: size)
    }
}

/// A City widget for the city with id `cityID`.
@MainActor
func readmeCity(_ cityID: String, _ options: ClockOptions) -> some View {
    let size = ClockFamily.small.nominalSize
    let clock = CityClock(city: city(cityID), date: referenceDate, local: newYork)
    return DesktopWidget(size: size) {
        CityLayout(clock: clock, options: options, size: size)
    }
}

@MainActor
func renderReadme() {
    // Top of the README: World Clock (medium), analog and digital; City (New York by day, Dhaka at night).
    write(ReadmeImage {
        VStack(spacing: readmeGap) {
            HStack(spacing: readmeGap) {
                readmeWorldClock(.medium, readmeAnalog)
                readmeWorldClock(.medium, readmeDigital)
            }
            HStack(spacing: readmeGap) {
                readmeCity("199", readmeAnalog)
                readmeCity("78", readmeAnalog)
                readmeCity("199", readmeDigital)
                readmeCity("78", readmeDigital)
            }
        }
    }, "hero")

    // Every World Clock size: large (8 cities), small and medium (4), extra large (12).
    write(ReadmeImage {
        VStack(spacing: readmeGap) {
            HStack(alignment: .top, spacing: readmeGap) {
                readmeWorldClock(.large, readmeAnalog)
                VStack(spacing: readmeGap) {
                    HStack(spacing: readmeGap) {
                        readmeWorldClock(.small, readmeAnalog)
                        readmeWorldClock(.small, readmeDigital)
                    }
                    readmeWorldClock(.medium, readmeDigital)
                }
            }
            readmeWorldClock(.extraLarge, readmeDigital)
        }
    }, "sizes")

    // The digital options: 12-hour with seconds, 24-hour with seconds, without seconds.
    write(ReadmeImage {
        HStack(spacing: readmeGap) {
            readmeCity("199", readmeDigital)
            readmeCity("199", ClockOptions(style: .digital, showsSeconds: true, hourCycle: .twentyFourHour))
            readmeCity("199", ClockOptions(style: .digital, showsSeconds: false, hourCycle: .twelveHour))
        }
    }, "digital-options")
}

MainActor.assumeIsolated {
    if iconMode {
        renderIcon()
    } else if iosIconMode {
        renderIOSIcon()
    } else if readmeMode {
        renderReadme()
    } else {
        renderAll()
        renderDigitalSheet()
    }
}
if written.isEmpty { fail("no images written") }
do {
    try (written.joined(separator: "\n") + "\n").write(to: outputDir.appendingPathComponent("manifest.txt"),
                                                      atomically: true, encoding: .utf8)
} catch {
    fail("could not write manifest.txt: \(error.localizedDescription)")
}
exit(failures.isEmpty ? 0 : 1)
