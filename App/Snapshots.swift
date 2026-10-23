import SwiftUI

/// `Stracotto --dump` prints the live reading. `Stracotto --snapshot <dir>` renders the popover in each power state to PNG and exits. Used to compare against reference shots.
enum Snapshots {
    static func sampleStates() -> [(String, BatterySnapshot)] {
        var base = BatterySnapshot()
        base.cycleCount = 349; base.designCycleCount = 1000; base.health = 89; base.condition = "Good"
        base.designCapacity = 4563; base.fullChargeCapacity = 3785; base.remainingCapacity = 3028
        base.temperature = 31.4; base.voltage = 12.61; base.adapterWatts = 36; base.hardwarePercent = 80.0

        var charging = base
        charging.percent = 80; charging.state = .charging; charging.isPluggedIn = true; charging.minutesRemaining = 42; charging.amperage = 1.23
        charging.flow = PowerFlow(adapterToSystem: 20.16, adapterToBattery: 15.52, batteryToSystem: 0, systemLoad: 20.16)
        var paused = base
        paused.percent = 80; paused.state = .paused; paused.isPluggedIn = true
        paused.flow = PowerFlow(adapterToSystem: 21.07, adapterToBattery: 0, batteryToSystem: 0, systemLoad: 21.07)
        var draining = base
        draining.percent = 79; draining.state = .pluggedDraining; draining.isPluggedIn = true; draining.minutesRemaining = 95; draining.amperage = -2.6
        draining.flow = PowerFlow(adapterToSystem: 28.39, adapterToBattery: 0, batteryToSystem: 32.93, systemLoad: 61.32)
        var battery = base
        battery.percent = 27; battery.state = .onBattery; battery.minutesRemaining = 130; battery.adapterWatts = nil; battery.amperage = -1.48
        battery.flow = PowerFlow(adapterToSystem: 0, adapterToBattery: 0, batteryToSystem: 19.4, systemLoad: 14.62, soc: 1.55, display: 1.46)
        battery.percent = 34

        // Same numbers as the user's AlDente reference screenshot, for side-by-side comparison.
        var reference = base
        reference.percent = 34; reference.state = .onBattery; reference.minutesRemaining = 48; reference.adapterWatts = nil
        reference.cycleCount = 558; reference.health = 79; reference.fullChargeCapacity = 4779; reference.temperature = 28.1
        reference.amperage = -1.76; reference.voltage = 11.0
        reference.flow = PowerFlow(adapterToSystem: 0, adapterToBattery: 0, batteryToSystem: 19.4, systemLoad: 14.62, soc: 1.55, display: 1.46)
        return [("charging", charging), ("paused", paused), ("draining", draining), ("battery", battery), ("reference", reference)]
    }

    @MainActor private static var previewWindow: NSWindow?

    /// `Stracotto --preview <charging|paused|draining|battery>` opens the popover content in a real window with sample
    /// data. Liquid Glass only renders in a live window, so this is how the glass gets checked.
    @MainActor static func preview(_ name: String) {
        DispatchQueue.main.async {
            let samples = sampleStates()
            guard let snap = samples.first(where: { $0.0 == name })?.1 else { return }
            let view = PopoverView()
                .padding(.vertical, 6)
                .environment(BatteryMonitor(fixed: snap))
                .environment(EnergyMonitor(fixed: name == "draining" ? sampleApps : []))
                .environment(ChargeController())
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Stracotto Preview – \(name)"
            window.isReleasedWhenClosed = false
            window.center()
            NSApp.setActivationPolicy(.regular)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            previewWindow = window
        }
    }

    static let sampleApps = [
        EnergyMonitor.AppEnergy(id: "/Applications/Xcode.app", name: "Xcode", watts: 9.4),
        EnergyMonitor.AppEnergy(id: "/Applications/Google Chrome.app", name: "Google Chrome", watts: 3.1),
        EnergyMonitor.AppEnergy(id: "/System/Applications/Music.app", name: "Music", watts: 1.2),
    ]

    @MainActor static func runIfRequested() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--preview"), i + 1 < args.count { preview(args[i + 1]); return }
        if let i = args.firstIndex(of: "--export-icon"), i + 1 < args.count {
            let renderer = ImageRenderer(content: AppIconArt().frame(width: 1024, height: 1024))
            renderer.scale = 1
            if let cg = renderer.cgImage {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: args[i + 1]))
            }
            exit(0)
        }
        if args.contains("--dump") {
            let monitor = BatteryMonitor()
            RunLoop.main.run(until: Date().addingTimeInterval(3)) // let the system_profiler health read land
            dump(monitor.snapshot)
            exit(0)
        }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        Theme.flatGlass = true
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let (charging, paused, draining, battery) = { let x = sampleStates(); return (x[0].1, x[1].1, x[2].1, x[3].1) }()
        UserDefaults.standard.set(true, forKey: ChargePrefs.sailing)
        UserDefaults.standard.set(5.0, forKey: ChargePrefs.sailingRange)
        UserDefaults.standard.set(false, forKey: Prefs.showHardwarePercent)
        UserDefaults.standard.set(false, forKey: AppearancePrefs.showPowerMode)
        for (name, snap) in sampleStates() {
            let apps = name == "draining" ? [
                EnergyMonitor.AppEnergy(id: "/Applications/Xcode.app", name: "Xcode", watts: 9.4),
                EnergyMonitor.AppEnergy(id: "/Applications/Google Chrome.app", name: "Google Chrome", watts: 3.1),
                EnergyMonitor.AppEnergy(id: "/System/Applications/Music.app", name: "Music", watts: 1.2),
            ] : []
            let view = PopoverView()
                .environment(BatteryMonitor(fixed: snap))
                .environment(EnergyMonitor(fixed: apps))
                .environment(ChargeController())
                .environment(\.colorScheme, .dark)
                .background(Theme.backdrop)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        // Menu bar item on a dark and a light bar.
        for (name, snap, scheme) in [("menubar-charging", charging, ColorScheme.dark), ("menubar-battery-low", { var b = battery; b.percent = 14; return b }(), .light), ("menubar-paused", paused, .dark)] {
            let bar = MenuBarIcon()
                .environment(BatteryMonitor(fixed: snap))
                .environment(EnergyMonitor(fixed: name == "menubar-charging" ? [.init(id: "/Applications/Xcode.app", name: "Xcode", watts: 9)] : []))
                .padding(6)
                .background(scheme == .dark ? Color(white: 0.12) : Color(white: 0.92))
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: bar)
            renderer.scale = 4
            if let cg = renderer.cgImage {
                try? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        exit(0)
    }
}
