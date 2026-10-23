import Charts
import SwiftUI

enum ChargePrefs {
    static let stopWhenSleeping = "charge.stopWhenSleeping"
    static let stopWhenClosed = "charge.stopWhenClosed"
    static let automaticDischarge = "charge.automaticDischarge"
    static let disableSleepUntilLimit = "charge.disableSleepUntilLimit"
    static let heatProtection = "charge.heatProtection"
    static let heatMaxTemp = "charge.heatMaxTemp"
    static let sailing = "charge.sailing"
    static let sailingRange = "charge.sailingRange"
    static let magSafeLED = "charge.magSafeLED"
}

/// Sidebar + grouped glass cards, after AlDente's settings window.
struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard", schedule = "Schedule", general = "General", charge = "Charge",
             features = "Features", appearance = "Appearance", popover = "Popup Window"
        var id: Self { self }
        var icon: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .schedule: "calendar.badge.clock"
            case .general: "gearshape.fill"
            case .charge: "bolt.batteryblock.fill"
            case .features: "books.vertical.fill"
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
            .navigationSplitViewColumnWidth(200)
            .safeAreaInset(edge: .bottom) {
                Text("Stracotto \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
        } detail: {
            ScrollView {
                GlassEffectContainer(spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        switch page {
                        case .dashboard: DashboardPage()
                        case .schedule: SchedulePage()
                        case .general: GeneralPage()
                        case .charge: ChargePage()
                        case .features: FeaturesPage()
                        case .appearance: AppearancePage()
                        case .popover: PopoverPage()
                        }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .id(page)
                .transition(.opacity.combined(with: .offset(y: 8)))
            }
            .scrollEdgeEffectStyle(.soft, for: .top)
            .animation(.smooth(duration: 0.3), value: page)
        }
        .frame(width: 760, height: 560)
    }
}

/// Section header + rounded glass card of rows, the unit every settings page is built from.
struct SettingsSection<Content: View>: View {
    let title: String, icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.system(size: 14, weight: .semibold))
            VStack(spacing: 14) { content }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard(radius: 20)
        }
        .padding(.bottom, 20)
    }
}

struct ToggleRow: View {
    let title: String, icon: String
    var help: String? = nil
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn.animation(.smooth(duration: 0.3))) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
                if let help { Image(systemName: "questionmark.circle").foregroundStyle(.tertiary).help(help) }
            }
        }
        .toggleStyle(.switch)
    }
}

/// Shown on pages whose switches are remembered but don't reach the hardware yet.
private struct BackendNotice: View {
    @Environment(ChargeController.self) private var charge
    var body: some View {
        if case .unavailable(let reason) = charge.backendStatus {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(reason).font(.system(size: 13, weight: .semibold))
                    Text("Your choices here are saved and take effect as soon as charge control is enabled on macOS 27.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.draining)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard(radius: 18, tint: Theme.draining.opacity(0.18))
            .padding(.bottom, 20)
        }
    }
}

// MARK: - Pages

private struct DashboardPage: View {
    @Environment(BatteryMonitor.self) private var monitor
    @Environment(ChargeController.self) private var charge

    var body: some View {
        @Bindable var charge = charge
        let s = monitor.snapshot
        SettingsSection(title: s.state.title, icon: "bolt.fill") {
            BatteryBar(percent: s.percent, state: s.state, plugEvents: monitor.plugEvents, height: 34,
                       limit: $charge.limit, limitLocked: charge.isToppingUp)
            PowerFlowView(flow: s.flow, state: s.state, adapterWatts: s.adapterWatts, plugEvents: monitor.plugEvents, height: 190)
        }
        SettingsSection(title: "Charge History", icon: "chart.xyaxis.line") {
            if monitor.history.count < 2 {
                Text("Collecting… a point is added every minute while Stracotto runs.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(monitor.history) { sample in
                    AreaMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.color(for: s.state).opacity(0.25).gradient)
                    LineMark(x: .value("Time", sample.date), y: .value("Charge", sample.percent))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.color(for: s.state))
                }
                .chartYScale(domain: 0...100)
                .frame(height: 140)
            }
        }
        SettingsSection(title: "Specifications", icon: "info.circle") { SpecsGrid(snapshot: s) }
    }
}

private struct SchedulePage: View {
    @Environment(Scheduler.self) private var scheduler
    @State private var draftAction = Scheduler.Action.setLimit(80)
    @State private var draftDate = Scheduler.nextDate(hour: 9)
    @State private var draftRepeat = Scheduler.Repeat.daily

    private static let actions: [Scheduler.Action] = [.setLimit(80), .startCalibration, .topUp, .pauseCharging, .dischargeTo(50), .lowPowerOn, .lowPowerOff]

    var body: some View {
        @Bindable var scheduler = scheduler
        BackendNotice()
        SettingsSection(title: "New Task", icon: "plus.circle") {
            Picker("Action", selection: $draftAction) {
                ForEach(Self.actions, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            HStack {
                DatePicker("Time", selection: $draftDate)
                Picker("Repeat", selection: $draftRepeat) { ForEach(Scheduler.Repeat.allCases) { Text($0.rawValue).tag($0) } }
                    .frame(width: 180)
            }
            HStack {
                Menu("Templates") {
                    ForEach(Scheduler.templates, id: \.name) { t in Button(t.name) { scheduler.add(t.task) } }
                }
                .fixedSize()
                Spacer()
                Button("Add Task") { scheduler.add(.init(action: draftAction, date: draftDate, repeats: draftRepeat)) }
                    .buttonStyle(.glassProminent)
            }
            ToggleRow(title: "Automatically Catch Up on Missed Tasks", icon: "clock.arrow.circlepath", isOn: $scheduler.catchUpMissed)
        }
        SettingsSection(title: "Tasks", icon: "list.bullet") {
            if scheduler.tasks.isEmpty {
                Text("No tasks yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 40)
            }
            ForEach($scheduler.tasks) { $task in
                HStack(spacing: 10) {
                    Image(systemName: task.action.icon).frame(width: 20)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.action.title).font(.system(size: 13, weight: .semibold))
                        Text("\(task.date.formatted(date: .abbreviated, time: .shortened)) · \(task.repeats.rawValue)")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $task.enabled).toggleStyle(.switch).labelsHidden()
                    Button { withAnimation(.smooth) { scheduler.remove(task) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.smooth(duration: 0.3), value: scheduler.tasks)
        SettingsSection(title: "Task History", icon: "clock") {
            if scheduler.history.isEmpty {
                Text("Nothing has run yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 40)
            }
            ForEach(scheduler.history.prefix(20)) { entry in
                HStack {
                    Text(entry.title).font(.system(size: 12, weight: .medium))
                    if let note = entry.note { Text(note).font(.system(size: 11)).foregroundStyle(.secondary) }
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct GeneralPage: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        SettingsSection(title: "General", icon: "gearshape") {
            ToggleRow(title: "Launch at Login", icon: "power", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }
        }
    }
}

private struct ChargePage: View {
    @AppStorage(ChargePrefs.stopWhenSleeping) private var stopWhenSleeping = false
    @AppStorage(ChargePrefs.stopWhenClosed) private var stopWhenClosed = false
    @AppStorage(ChargePrefs.automaticDischarge) private var automaticDischarge = false
    @AppStorage(ChargePrefs.disableSleepUntilLimit) private var disableSleep = false
    @AppStorage(Prefs.showHardwarePercent) private var showHardwarePercent = false

    var body: some View {
        BackendNotice()
        SettingsSection(title: "Charging", icon: "bolt.circle") {
            ToggleRow(title: "Stop charging when sleeping", icon: "moon.fill",
                      help: "Pauses charging just before sleep so the battery stays where it is.", isOn: $stopWhenSleeping)
            ToggleRow(title: "Stop charging when app closed", icon: "power",
                      help: "Keeps the limit after quitting or logging out. Resets when the Mac shuts down.", isOn: $stopWhenClosed)
            ToggleRow(title: "Automatic Discharge", icon: "bolt.slash",
                      help: "Drains to the limit whenever the battery is above it, even while plugged in.", isOn: $automaticDischarge)
        }
        SettingsSection(title: "Sleep", icon: "moon.circle") {
            ToggleRow(title: "Disable Sleep until Charge Limit", icon: "bed.double.fill",
                      help: "Keeps the Mac awake until it reaches the limit, then allows sleep.", isOn: $disableSleep)
        }
        SettingsSection(title: "Other", icon: "ellipsis.circle") {
            ToggleRow(title: "Hardware Battery Percentage", icon: "info.circle",
                      help: "Shows the battery gauge's own reading next to the macOS value.", isOn: $showHardwarePercent)
        }
    }
}

private struct FeaturesPage: View {
    @Environment(ChargeController.self) private var charge
    @AppStorage(ChargePrefs.heatProtection) private var heatProtection = false
    @AppStorage(ChargePrefs.heatMaxTemp) private var heatMaxTemp = 35.0
    @AppStorage(ChargePrefs.sailing) private var sailing = false
    @AppStorage(ChargePrefs.sailingRange) private var sailingRange = 5.0
    @AppStorage(ChargePrefs.magSafeLED) private var magSafeLED = true

    var body: some View {
        BackendNotice()
        SettingsSection(title: "Heat Protection", icon: "thermometer.sun.fill") {
            ToggleRow(title: "Stop charging when the battery is hot", icon: "flame",
                      help: "Uses 5-minute windows so charging doesn't flicker on and off.", isOn: $heatProtection)
            if heatProtection {
                HStack {
                    Text("Max. Temp.").font(.system(size: 13))
                    Slider(value: $heatMaxTemp, in: 30...45, step: 1)
                    Text("\(Int(heatMaxTemp))°C").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        SettingsSection(title: "Sailing Mode", icon: "sailboat.fill") {
            ToggleRow(title: "Let the battery drift below the limit", icon: "arrow.down.right",
                      help: "Only recharges after dropping this far below the limit, so it isn't topped up constantly.", isOn: $sailing)
            if sailing {
                HStack {
                    Text("Range").font(.system(size: 13))
                    Slider(value: $sailingRange, in: 1...20, step: 1)
                    Text("\(Int(sailingRange))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        SettingsSection(title: "Calibration Mode", icon: "arrow.triangle.2.circlepath") {
            HStack {
                Text("Charges to 100%, drains to 10%, recharges to 100%, holds for an hour, then returns to your limit.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Start Calibration") {}
                    .buttonStyle(.glass)
                    .disabled(charge.backendStatus != .ready)
            }
        }
        SettingsSection(title: "MagSafe LED", icon: "light.beacon.max.fill") {
            ToggleRow(title: "Indicate Charge Limit", icon: "lightbulb",
                      help: "Green at the limit, orange while charging or discharging toward it.", isOn: $magSafeLED)
        }
    }
}

private struct AppearancePage: View {
    @AppStorage(Prefs.menuBarEnergyAlert) private var showEnergyAlert = true

    var body: some View {
        SettingsSection(title: "Menu Bar", icon: "menubar.rectangle") {
            ToggleRow(title: "Flame When an App Uses a Lot of Energy", icon: "flame", isOn: $showEnergyAlert)
        }
        SettingsSection(title: "Menu Bar Battery", icon: "sparkles") {
            HStack(spacing: 22) {
                ForEach(Array([(PowerState.charging, 46), (.paused, 80), (.onBattery, 64), (.onBattery, 14)].enumerated()), id: \.offset) { _, item in
                    let (state, level) = item
                    VStack(spacing: 10) {
                        AppleBattery(percent: level, state: state, plugEvents: 0).scaleEffect(1.7).frame(height: 26)
                        Text(level < 20 ? "Low" : state.title).font(.system(size: 10)).foregroundStyle(.secondary)
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
