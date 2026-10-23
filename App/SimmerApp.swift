import ServiceManagement
import SwiftUI

enum Prefs {
    static let showPowerFlow = "showPowerFlow"
    static let showSpecs = "showSpecs"
    static let showHardwarePercent = "showHardwarePercent"
    static let menuBarPercent = "menuBarPercent"
    static let menuBarIcon = "menuBarIcon"
}

@main
struct SimmerApp: App {
    @State private var monitor: BatteryMonitor

    init() {
        Snapshots.runIfRequested()
        _monitor = State(initialValue: BatteryMonitor())
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView().environment(monitor)
        } label: {
            MenuBarLabel(snapshot: monitor.snapshot)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView().environment(monitor)
        }
    }
}

/// Menu bar items only take Text and Image, so the live glyph is rendered to a template image.
struct MenuBarLabel: View {
    let snapshot: BatterySnapshot
    @AppStorage(Prefs.menuBarPercent) private var showPercent = true
    @AppStorage(Prefs.menuBarIcon) private var showIcon = true

    var body: some View {
        HStack(spacing: 4) {
            if showPercent { Text("\(snapshot.percent)%").monospacedDigit() }
            if showIcon || !showPercent { Image(nsImage: Self.render(snapshot.state)) }
        }
    }

    @MainActor static func render(_ state: PowerState) -> NSImage {
        let renderer = ImageRenderer(content: StatusGlyph(state: state, size: 13).foregroundStyle(.black).padding(.vertical, 1))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ enabled: Bool) {
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}
