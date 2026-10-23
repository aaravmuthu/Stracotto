import Charts
import SwiftUI

/// Sidebar + grouped cards, after AlDente's settings window.
struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard", general = "General", appearance = "Appearance", popover = "Popup Window"
        var id: Self { self }
        var icon: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .general: "gearshape.fill"
            case .appearance: "paintbrush.pointed.fill"
            case .popover: "macwindow"
            }
        }
    }

    @State private var page = Page.dashboard

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(190)
            .safeAreaInset(edge: .bottom) {
                Text("Stracotto \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        } detail: {
            ScrollView {
                Group {
                    switch page {
                    case .dashboard: DashboardPage()
                    case .general: GeneralPage()
                    case .appearance: AppearancePage()
                    case .popover: PopoverPage()
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .id(page)
                .transition(.opacity.combined(with: .offset(y: 6)))
            }
            .animation(.easeOut(duration: 0.22), value: page)
        }
        .frame(width: 720, height: 520)
    }
}

/// Section header + rounded card of rows, the unit every settings page is built from.
struct SettingsSection<Content: View>: View {
    let title: String, icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
            VStack(spacing: 14) { content }
                .padding(16)
                .background(Theme.chip, in: .rect(cornerRadius: 16))
        }
        .padding(.bottom, 18)
    }
}

struct ToggleRow: View {
    let title: String, icon: String
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn) { Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold)) }
            .toggleStyle(.switch)
    }
}

private struct DashboardPage: View {
    @Environment(BatteryMonitor.self) private var monitor

    var body: some View {
        let s = monitor.snapshot
        SettingsSection(title: s.state.title, icon: "bolt.fill") {
            BatteryBar(percent: s.percent, state: s.state, plugEvents: monitor.plugEvents, height: 34)
            PowerFlowView(flow: s.flow, state: s.state, adapterWatts: s.adapterWatts, plugEvents: monitor.plugEvents, height: 190)
        }
        SettingsSection(title: "Charge History", icon: "chart.xyaxis.line") {
            if monitor.history.count < 2 {
                Text("Collecting… a point is added every minute while Stracotto runs.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(monitor.history) { sample in
                    AreaMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent))
                        .foregroundStyle(Theme.color(for: s.state).opacity(0.25).gradient)
                    LineMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent))
                        .foregroundStyle(Theme.color(for: s.state))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 140)
            }
        }
        SettingsSection(title: "Specifications", icon: "info.circle") { SpecsGrid(snapshot: s) }
    }
}

private struct GeneralPage: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @AppStorage(Prefs.showHardwarePercent) private var showHardwarePercent = false

    var body: some View {
        SettingsSection(title: "General", icon: "gearshape") {
            ToggleRow(title: "Launch at Login", icon: "power", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }
        }
        SettingsSection(title: "Other", icon: "ellipsis.circle") {
            ToggleRow(title: "Hardware Battery Percentage", icon: "info.circle", isOn: $showHardwarePercent)
        }
    }
}

private struct AppearancePage: View {
    @AppStorage(Prefs.menuBarPercent) private var showPercent = true
    @AppStorage(Prefs.menuBarIcon) private var showIcon = true
    @AppStorage(Prefs.menuBarEnergyAlert) private var showEnergyAlert = true

    var body: some View {
        SettingsSection(title: "Menu Bar", icon: "menubar.rectangle") {
            ToggleRow(title: "Show Percentage", icon: "percent", isOn: $showPercent)
            ToggleRow(title: "Show Battery Icon", icon: "battery.75percent", isOn: $showIcon)
            ToggleRow(title: "Flame When an App Uses a Lot of Energy", icon: "flame", isOn: $showEnergyAlert)
        }
        SettingsSection(title: "Menu Bar Battery", icon: "sparkles") {
            HStack(spacing: 22) {
                ForEach(Array([(PowerState.charging, 80), (.paused, 80), (.onBattery, 64), (.onBattery, 14)].enumerated()), id: \.offset) { _, item in
                    let (state, level) = item
                    VStack(spacing: 8) {
                        AppleBattery(percent: level, state: state, plugEvents: 0).scaleEffect(1.6).frame(height: 24)
                        Text(level < 20 ? "Low" : state.title).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        SettingsSection(title: "Live Status Icons", icon: "sparkles") {
            HStack(spacing: 22) {
                ForEach([PowerState.charging, .paused, .pluggedDraining, .onBattery], id: \.self) { state in
                    VStack(spacing: 6) {
                        StatusGlyph(state: state, size: 16)
                        Text(state.title).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

private struct PopoverPage: View {
    @AppStorage(Prefs.showPowerFlow) private var showPowerFlow = true
    @AppStorage(Prefs.showSpecs) private var showSpecs = true
    @AppStorage(Prefs.showEnergyApps) private var showEnergyApps = true

    var body: some View {
        SettingsSection(title: "Widgets", icon: "square.stack") {
            ToggleRow(title: "Power Flow", icon: "point.3.connected.trianglepath.dotted", isOn: $showPowerFlow)
            ToggleRow(title: "Apps Using Significant Energy", icon: "flame", isOn: $showEnergyApps)
            ToggleRow(title: "Specifications", icon: "info.circle", isOn: $showSpecs)
        }
    }
}
