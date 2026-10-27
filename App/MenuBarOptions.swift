import AppKit
import SwiftUI

/// AlDente's "Main Icon Style" choices.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case native, status, percentage
    var id: Self { self }
    var title: String {
        switch self {
        case .native: "iOS Native"
        case .status: "Live Status"
        case .percentage: "Percentage Only"
        }
    }
    var width: CGFloat {
        switch self {
        case .native: AppleBattery.size.width
        case .status: 62
        case .percentage: 38
        }
    }
}

/// Extra stats that can sit next to the icon (Appearance → Menubar → Battery Specs).
enum MenuBarStat: String, CaseIterable, Identifiable {
    case hardwarePercent, power, temperature, timeRemaining, systemLoad
    var id: Self { self }
    var title: String {
        switch self {
        case .hardwarePercent: "Hardware Battery Percentage"
        case .power: "Battery Power"
        case .temperature: "Temperature"
        case .timeRemaining: "Time Remaining"
        case .systemLoad: "System Load"
        }
    }
    static let width: CGFloat = 46
    /// The time stat carries a state icon (clock / charger) on its leading side.
    var slotWidth: CGFloat { (self == .timeRemaining ? Self.width + 15 : Self.width) }

    func value(_ s: BatterySnapshot) -> String {
        switch self {
        case .hardwarePercent: s.hardwarePercent.formatted(.number.precision(.fractionLength(0))) + "%"
        case .power: (s.voltage * s.amperage).formatted(.number.precision(.fractionLength(1))) + "W"
        case .temperature: s.temperature.map {
            Measurement(value: $0, unit: UnitTemperature.celsius)
                .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
        } ?? "--"
        case .timeRemaining: s.minutesRemaining.map { "\($0 / 60):" + String(format: "%02d", $0 % 60) } ?? "--"
        case .systemLoad: s.flow.systemLoad.formatted(.number.precision(.fractionLength(1))) + "W"
        }
    }

    static func parse(_ raw: String) -> [MenuBarStat] { raw.split(separator: ",").compactMap { MenuBarStat(rawValue: String($0)) } }
    static func toggle(_ stat: MenuBarStat, in raw: String) -> String {
        var list = parse(raw)
        if let i = list.firstIndex(of: stat) { list.remove(at: i) } else { list.append(stat) }
        return list.map(\.rawValue).joined(separator: ",")
    }
}

/// Beside a time readout: a clock while draining; while a charger is attached, a charger that glows green as it fills
/// and sits yellow when it's plugged in but not filling.
struct TimeStateIcon: View {
    let state: PowerState
    var size: CGFloat = 12

    private var symbol: String {
        switch state {
        case .onBattery: "clock"
        case .charging: "bolt.fill"
        case .paused, .pluggedDraining: "powerplug.portrait.fill"
        }
    }

    private var color: Color? {
        switch state {
        case .onBattery: nil
        case .charging: Theme.charging
        case .paused, .pluggedDraining: Theme.bolt
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color ?? Theme.text)
            // A soft halo only while a charger is involved, like the icon is lit from behind.
            .shadow(color: (color ?? .clear).opacity(color == nil ? 0 : 0.85), radius: 3)
            .shadow(color: (color ?? .clear).opacity(color == nil ? 0 : 0.45), radius: 7)
            .contentTransition(.symbolEffect(.replace.downUp))
            .animation(.smooth(duration: 0.4), value: state)
    }
}

enum RightClickAction: String, CaseIterable, Identifiable {
    case dashboard, topUp, menu
    var id: Self { self }
    var title: String {
        switch self {
        case .dashboard: "Open Dashboard"
        case .topUp: "Toggle Top Up"
        case .menu: "Show Menu"
        }
    }
}

enum AppearanceMode {
    @MainActor static func apply(_ mode: String) {
        NSApp.appearance = switch mode {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}
