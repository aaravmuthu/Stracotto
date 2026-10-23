import ServiceManagement
import SwiftUI

enum Prefs {
    static let chargeLimit = "chargeLimit"
    static let showPowerFlow = "showPowerFlow"
    static let showSpecs = "showSpecs"
    static let showEnergyApps = "showEnergyApps"
    static let showHardwarePercent = "showHardwarePercent"
    static let menuBarPercent = "menuBarPercent"
    static let menuBarIcon = "menuBarIcon"
    static let menuBarEnergyAlert = "menuBarEnergyAlert"
}

/// A reference type so views compare it by identity instead of re-rendering on every environment pass.
final class SettingsOpener: Sendable {
    private let open: @MainActor @Sendable () -> Void
    init(_ open: @escaping @MainActor @Sendable () -> Void) { self.open = open }
    @MainActor func callAsFunction() { open() }
    static let none = SettingsOpener {}
}

extension EnvironmentValues {
    @Entry var showSettings: SettingsOpener = .none
}

@main
struct StracottoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { Snapshots.runIfRequested() }

    // The menu bar item and windows are AppKit-owned (see StatusController); this scene only satisfies App.
    var body: some Scene { Settings { EmptyView() } }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: StatusController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--preview") { return }
        status = StatusController(battery: BatteryMonitor(), energy: EnergyMonitor(), charge: ChargeController())
    }
}

/// Owns the status item, its popover, and the settings window.
@MainActor
final class StatusController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private let battery: BatteryMonitor
    private let energy: EnergyMonitor
    private let charge: ChargeController
    private let scheduler: Scheduler

    init(battery: BatteryMonitor, energy: EnergyMonitor, charge: ChargeController) {
        self.battery = battery
        self.energy = energy
        self.charge = charge
        self.scheduler = Scheduler(charge: charge)
        statusItem = SystemBatteryIcon.makeStatusItem()
        super.init()
        battery.onUpdate = { [weak charge] snapshot in charge?.batteryChanged(snapshot) }

        guard let button = statusItem.button else { return }
        let icon = PassthroughHostingView(rootView: MenuBarIcon()
            .environment(battery)
            .environment(energy)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { [weak self] width in
                self?.statusItem.length = ceil(width)
            })
        icon.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(icon)
        NSLayoutConstraint.activate([
            icon.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        AppearanceMode.apply(UserDefaults.standard.string(forKey: AppearancePrefs.mode) ?? "system")

        // The popover is resized by hand from the content's ideal height, inside an animation group, so the window
        // grows in step with SwiftUI's transitions instead of snapping a frame later.
        let content = NSHostingController(rootView: PopoverView()
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self, of: \.size.height) { [weak self] height in self?.resizePopover(to: height) }
            .frame(maxHeight: .infinity, alignment: .top)
            // AlDente's popover is dark and calm; tone down the desktop showing through the popover glass.
            .background(Theme.backdrop.opacity(0.94))
            .environment(battery)
            .environment(energy)
            .environment(charge)
            .environment(\.showSettings, SettingsOpener { [weak self] in self?.showSettings() }))
        content.sizingOptions = []
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    @objc private func statusItemClicked() {
        guard NSApp.currentEvent?.type == .rightMouseUp else { return togglePopover() }
        switch RightClickAction(rawValue: UserDefaults.standard.string(forKey: AppearancePrefs.rightClick) ?? "") ?? .dashboard {
        case .dashboard: showSettings()
        case .topUp: charge.toggleTopUp()
        case .menu:
            let menu = NSMenu()
            menu.addItem(withTitle: "Open Dashboard", action: #selector(openDashboardFromMenu), keyEquivalent: "").target = self
            menu.addItem(withTitle: charge.isToppingUp ? "Stop Top Up" : "Top Up", action: #selector(toggleTopUpFromMenu), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit Stracotto", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        }
    }

    @objc private func openDashboardFromMenu() { showSettings() }
    @objc private func toggleTopUpFromMenu() { charge.toggleTopUp() }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            button.highlight(true)
        }
    }

    func popoverDidClose(_ notification: Notification) { statusItem.button?.highlight(false) }

    private func resizePopover(to height: CGFloat) {
        let size = NSSize(width: 380, height: ceil(height))
        guard abs(popover.contentSize.height - size.height) > 0.5 else { return }
        guard popover.isShown else { popover.contentSize = size; return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            context.allowsImplicitAnimation = true
            popover.contentSize = size
        }
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()
                .environment(battery)
                .environment(energy)
                .environment(charge)
                .environment(scheduler)))
            window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.title = "Stracotto"
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Lets clicks fall through to the status bar button underneath.
final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static func set(_ enabled: Bool) {
        try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
    }
}
