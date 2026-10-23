import SwiftUI

/// `Simmer --dump` prints the live reading. `Simmer --snapshot <dir>` renders the popover in each power state to PNG and exits. Used to compare against reference shots.
enum Snapshots {
    @MainActor static func runIfRequested() {
        let args = CommandLine.arguments
        if args.contains("--dump") {
            let monitor = BatteryMonitor()
            RunLoop.main.run(until: Date().addingTimeInterval(3)) // let the system_profiler health read land
            dump(monitor.snapshot)
            exit(0)
        }
        guard let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count else { return }
        let dir = URL(fileURLWithPath: args[i + 1])
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

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
        battery.flow = PowerFlow(adapterToSystem: 0, adapterToBattery: 0, batteryToSystem: 18.63, systemLoad: 18.63)

        for (name, snap) in [("charging", charging), ("paused", paused), ("draining", draining), ("battery", battery)] {
            let view = PopoverView()
                .environment(BatteryMonitor(fixed: snap))
                .background(Color(white: 0.24))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let cg = renderer.cgImage {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        exit(0)
    }
}
