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
