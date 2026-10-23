import Charts
import SwiftUI

enum ChargePrefs {
    static let stopWhenSleeping = "charge.stopWhenSleeping"
    static let stopWhenClosed = "charge.stopWhenClosed"
    static let automaticDischarge = "charge.automaticDischarge"
    static let disableSleepUntilLimit = "charge.disableSleepUntilLimit"
    static let allowBelow80 = "charge.allowBelow80"
    static let heatProtection = "charge.heatProtection"
    static let heatMaxTemp = "charge.heatMaxTemp"
    static let sailing = "charge.sailing"
    static let sailingRange = "charge.sailingRange"
    static let magSafeLED = "charge.magSafeLED"
    static let magSafeBlink = "charge.magSafeBlink"
    static let magSafeMode = "charge.magSafeMode"
}

enum AppearancePrefs {
    static let mode = "appearance.mode"                 // system | light | dark
    static let reduceTransparency = "appearance.reduceTransparency"
    static let liquidGlass = "appearance.liquidGlass"
    static let iconStyle = "appearance.iconStyle"       // MenuBarStyle raw value
    static let stats = "appearance.menubarStats"        // comma-separated MenuBarStat raw values
    static let rightClick = "appearance.rightClick"     // RightClickAction raw value
    static let showPowerMode = "popover.showPowerMode"
    static let showBackgroundProcesses = "popover.showBackgroundProcesses"
}

/// Current AlDente settings layout: Dashboard, Battery Care, Automations, Appearance, General, with the version,
/// Quit and License at the foot of the sidebar.
struct SettingsView: View {
    enum Page: String, CaseIterable, Identifiable {
        case dashboard = "Dashboard", batteryCare = "Battery Care", automations = "Automations",
             appearance = "Appearance", general = "General"
        var id: Self { self }
        var icon: String {
            switch self {
            case .dashboard: "square.grid.2x2"
            case .batteryCare: "minus.plus.batteryblock.fill"
            case .automations: "calendar.badge.clock"
            case .appearance: "paintbrush.pointed.fill"
            case .general: "gearshape.fill"
            }
        }
    }

    @State private var page = Page.dashboard

    var body: some View {
        NavigationSplitView {
            List(Page.allCases, selection: $page) { p in
                Label(p.rawValue, systemImage: p.icon).tag(p)
            }
            .navigationSplitViewColumnWidth(210)
            .safeAreaInset(edge: .bottom) { SidebarFooter() }
        } detail: {
            ScrollView {
                Group { // no GlassEffectContainer: it composites glass above labels
                    VStack(alignment: .leading, spacing: 0) {
                        switch page {
                        case .dashboard: DashboardPage()
                        case .batteryCare: BatteryCarePage()
                        case .automations: AutomationsPage()
                        case .appearance: AppearancePage()
                        case .general: GeneralPage()
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
        .frame(width: 780, height: 580)
    }
}

/// Version + link, then the round Quit button and License, like AlDente's sidebar foot.
private struct SidebarFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
            AppIconArt().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Stracotto \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                    .font(.system(size: 12, weight: .semibold))
                Text("github.com/mks909/Stracotto").font(.system(size: 11)).foregroundStyle(Theme.paused)
            }
            }
            HStack {
                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power").font(.system(size: 15, weight: .semibold)).frame(width: 38, height: 34)
                }
                .buttonStyle(.plain)
                .liquidGlass(interactive: true, in: .rect(cornerRadius: 12, style: .continuous))
                .help("Quit Stracotto")
                Spacer()
                Text("License")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 84, height: 34)
                    .liquidGlass(in: .rect(cornerRadius: 12, style: .continuous))
                    .help("Stracotto is free — every Pro feature is included")
            }
        }
        .padding(16)
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
    var live = true
    @Binding var isOn: Bool
    var body: some View {
        Toggle(isOn: $isOn.animation(.smooth(duration: 0.3))) {
            HStack(spacing: 6) {
                Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
                if let help { Image(systemName: "questionmark.circle").foregroundStyle(.tertiary).help(help) }
                if !live {
                    Text("Saved only").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: .capsule)
                        .help("Remembered, but not enforced yet on macOS 27")
                }
            }
        }
        .toggleStyle(.switch)
    }
}

// MARK: - Dashboard

private struct DashboardPage: View {
    @Environment(BatteryMonitor.self) private var monitor
    @Environment(ChargeController.self) private var charge

    var body: some View {
        let s = monitor.snapshot
        SettingsSection(title: s.state.title, icon: "bolt.fill") {
            HStack {
                Text("Limit: \(charge.target)%").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(charge.isToppingUp ? "Topping Up" : "Top Up") { charge.toggleTopUp() }.buttonStyle(.glass)
                Button("Start Calibration") {}.buttonStyle(.glass).disabled(true).help("Needs charge control beyond macOS's limit")
            }
            BatteryBar(percent: s.percent, state: s.state, plugEvents: monitor.plugEvents, height: 30)
            PowerFlowView(flow: s.flow, state: s.state, adapterWatts: s.adapterWatts, plugEvents: monitor.plugEvents, height: 220)
        }
        SettingsSection(title: "Charge History", icon: "chart.xyaxis.line") {
            if monitor.history.count < 2 {
                Text("Collecting data… a point is added every minute while Stracotto runs.")
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
        SettingsSection(title: "Specifications", icon: "info.circle") { SpecsList(snapshot: s) }
    }
}

// MARK: - Battery Care

private struct BatteryCarePage: View {
    @Environment(ChargeController.self) private var charge
    @AppStorage(ChargePrefs.automaticDischarge) private var automaticDischarge = false
    @AppStorage(ChargePrefs.allowBelow80) private var allowBelow80 = false
    @AppStorage(ChargePrefs.stopWhenClosed) private var stopWhenClosed = false
    @AppStorage(ChargePrefs.heatProtection) private var heatProtection = false
    @AppStorage(ChargePrefs.heatMaxTemp) private var heatMaxTemp = 35.0
    @AppStorage(ChargePrefs.sailing) private var sailing = false
    @AppStorage(ChargePrefs.sailingRange) private var sailingRange = 5.0
    @AppStorage(ChargePrefs.disableSleepUntilLimit) private var disableSleep = false
    @AppStorage(ChargePrefs.stopWhenSleeping) private var stopWhenSleeping = false

    var body: some View {
        @Bindable var charge = charge
        SettingsSection(title: "Charge Limit", icon: "battery.75percent") {
            Picker(selection: $charge.limit) {
                ForEach(charge.allowedLimits, id: \.self) { Text($0 == 100 ? "Off" : "\($0)%").tag($0) }
            } label: {
                Label("Charge Limit", systemImage: "slider.horizontal.3").font(.system(size: 13, weight: .semibold))
            }
            .pickerStyle(.segmented)
            Text("Uses macOS's built-in limit, so it stays in sync with System Settings → Battery → Charging.")
                .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            ToggleRow(title: "Allow Charge Limits Below 80%", icon: "battery.25percent", live: false, isOn: $allowBelow80)
        }
        SettingsSection(title: "Charge Control", icon: "bolt.circle") {
            ToggleRow(title: "Automatic Discharge", icon: "bolt.slash",
                      help: "Drains to the limit whenever the battery is above it, even while plugged in.", live: false, isOn: $automaticDischarge)
            ToggleRow(title: "Stop Charging when App Closed", icon: "power",
                      help: "Keeps the limit after quitting. macOS's limit already persists, so this is on in practice.", isOn: .constant(true))
                .disabled(true)
            ToggleRow(title: "Heat Protection", icon: "thermometer.sun",
                      help: "Stops charging when the battery is hotter than Max. Temp. Uses 5-minute windows.", live: false, isOn: $heatProtection)
            if heatProtection {
                HStack {
                    Text("Max. Temp.").font(.system(size: 13))
                    Slider(value: $heatMaxTemp, in: 30...50, step: 1)
                    Text(Measurement(value: heatMaxTemp, unit: UnitTemperature.celsius)
                        .formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))))
                        .monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ToggleRow(title: "Sailing Mode", icon: "sailboat",
                      help: "Only recharges after dropping this far below the limit.", live: false, isOn: $sailing)
            if sailing {
                HStack {
                    Text("Sailing Range").font(.system(size: 13))
                    Slider(value: $sailingRange, in: 1...20, step: 1)
                    Text("\(Int(sailingRange))%").monospacedDigit().frame(width: 52, alignment: .trailing)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            HStack {
                Label("Calibration Mode", systemImage: "arrow.triangle.2.circlepath").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Start Calibration") {}.buttonStyle(.glass).disabled(true)
            }
        }
        SettingsSection(title: "Sleep Behavior", icon: "moon.circle") {
            ToggleRow(title: "Disable Sleep until Charge Limit", icon: "bed.double",
                      help: "Keeps the Mac awake until it reaches the limit, then allows sleep.", live: false, isOn: $disableSleep)
            ToggleRow(title: "Stop Charging when Sleeping", icon: "moon.zzz",
                      help: "Pauses charging just before sleep.", live: false, isOn: $stopWhenSleeping)
                .disabled(disableSleep)
        }
    }
}

// MARK: - Automations

private struct AutomationsPage: View {
    @Environment(Scheduler.self) private var scheduler
    @State private var draftAction = Scheduler.Action.setLimit(80)
    @State private var draftDate = Scheduler.nextDate(hour: 9)
    @State private var draftRepeat = Scheduler.Repeat.daily
    @State private var adding = false

    private static let actions: [Scheduler.Action] = [.setLimit(80), .startCalibration, .topUp, .pauseCharging, .dischargeTo(50), .lowPowerOn, .lowPowerOff]

    var body: some View {
        @Bindable var scheduler = scheduler
        SettingsSection(title: "Schedule", icon: "calendar") {
            HStack {
                Text("Tasks").font(.system(size: 13, weight: .semibold))
                Spacer()
                Menu("Templates") {
                    ForEach(Scheduler.templates, id: \.name) { t in Button(t.name) { withAnimation(.smooth) { scheduler.add(t.task) } } }
                }
                .fixedSize()
                Button { withAnimation(.smooth) { adding.toggle() } } label: { Image(systemName: adding ? "xmark" : "plus") }
                    .buttonStyle(.glass)
            }
            if adding {
                VStack(spacing: 10) {
                    Picker("Action", selection: $draftAction) {
                        ForEach(Self.actions, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                    }
                    HStack {
                        DatePicker("Start Time", selection: $draftDate)
                        Picker("Repeat", selection: $draftRepeat) { ForEach(Scheduler.Repeat.allCases) { Text($0.rawValue).tag($0) } }
                            .frame(width: 190)
                    }
                    HStack {
                        Spacer()
                        Button("Add Task") {
                            withAnimation(.smooth) {
                                scheduler.add(.init(action: draftAction, date: draftDate, repeats: draftRepeat))
                                adding = false
                            }
                        }
                        .buttonStyle(.glassProminent)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if scheduler.tasks.isEmpty && !adding {
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
                    Toggle("Active", isOn: $task.enabled).toggleStyle(.switch).labelsHidden().help("Active")
                    Button { withAnimation(.smooth) { scheduler.remove(task) } } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ToggleRow(title: "Automatically Catch Up on Missed Tasks", icon: "clock.arrow.circlepath", isOn: $scheduler.catchUpMissed)
        }
        .animation(.smooth(duration: 0.3), value: scheduler.tasks)
        SettingsSection(title: "Task History", icon: "clock") {
            HStack {
                Spacer()
                Button("Clear History") { withAnimation(.smooth) { scheduler.clearHistory() } }
                    .buttonStyle(.glass).disabled(scheduler.history.isEmpty)
            }
            if scheduler.history.isEmpty {
                Text("Nothing has run yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 40)
            }
            ForEach(scheduler.history.prefix(30)) { entry in
                HStack(spacing: 10) {
                    Circle().fill(entry.note == nil ? Theme.charging : Theme.draining).frame(width: 7, height: 7)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(entry.title).font(.system(size: 12, weight: .semibold))
                        if let note = entry.note { Text(note).font(.system(size: 11)).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(entry.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Appearance

private struct AppearancePage: View {
    @AppStorage(AppearancePrefs.mode) private var mode = "system"
    @AppStorage(AppearancePrefs.reduceTransparency) private var reduceTransparency = false
    @AppStorage(AppearancePrefs.liquidGlass) private var liquidGlass = false
    @AppStorage(AppearancePrefs.iconStyle) private var iconStyle = MenuBarStyle.native.rawValue
    @AppStorage(AppearancePrefs.stats) private var stats = ""
    @AppStorage(AppearancePrefs.rightClick) private var rightClick = RightClickAction.dashboard.rawValue
    @AppStorage(Prefs.menuBarEnergyAlert) private var showEnergyAlert = true
    @AppStorage(Prefs.showPowerFlow) private var showPowerFlow = true
    @AppStorage(AppearancePrefs.showPowerMode) private var showPowerMode = true
    @AppStorage(Prefs.showEnergyApps) private var showEnergyApps = true
    @AppStorage(AppearancePrefs.showBackgroundProcesses) private var showBackground = false
    @AppStorage(Prefs.showSpecs) private var showSpecs = true
    @AppStorage(ChargePrefs.magSafeLED) private var magSafeLED = true
    @AppStorage(ChargePrefs.magSafeBlink) private var magSafeBlink = false
    @AppStorage(ChargePrefs.magSafeMode) private var magSafeMode = "system"

    var body: some View {
        SettingsSection(title: "Appearance", icon: "circle.lefthalf.filled") {
            Picker(selection: $mode) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            } label: { Label("Appearance", systemImage: "circle.lefthalf.filled").font(.system(size: 13, weight: .semibold)) }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, m in AppearanceMode.apply(m) }
            ToggleRow(title: "Liquid Glass Surfaces", icon: "drop.halffull",
                      help: "Real refractive glass that shows the desktop through. Off matches AlDente's solid slabs.", isOn: $liquidGlass)
            ToggleRow(title: "Reduce Transparency", icon: "square.on.square.dashed",
                      help: "Uses solid surfaces everywhere.", isOn: $reduceTransparency)
        }
        SettingsSection(title: "Menubar", icon: "menubar.rectangle") {
            Picker(selection: $iconStyle) {
                ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0.rawValue) }
            } label: { Label("Main Icon Style", systemImage: "battery.75percent").font(.system(size: 13, weight: .semibold)) }
            HStack(spacing: 22) {
                ForEach(Array([(PowerState.charging, 46), (.paused, 80), (.onBattery, 64), (.onBattery, 14)].enumerated()), id: \.offset) { _, item in
                    let (state, level) = item
                    VStack(spacing: 10) {
                        MenuBarGlyph(style: MenuBarStyle(rawValue: iconStyle) ?? .native, percent: level, state: state, plugEvents: 0)
                            .scaleEffect(1.6).frame(height: 26)
                        Text(level < 20 ? "Low" : state.title).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Label("Battery Specs", systemImage: "list.bullet").font(.system(size: 13, weight: .semibold))
                FlowLayout(spacing: 8) {
                    ForEach(MenuBarStat.allCases) { stat in
                        let on = MenuBarStat.parse(stats).contains(stat)
                        Button { stats = MenuBarStat.toggle(stat, in: stats) } label: {
                            Label(stat.title, systemImage: on ? "checkmark.circle.fill" : "plus.circle")
                                .font(.system(size: 12, weight: .medium))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(tint: on ? Theme.paused.opacity(0.5) : nil, interactive: true, in: .capsule)
                    }
                }
            }
            ToggleRow(title: "Flame When an App Uses a Lot of Energy", icon: "flame", isOn: $showEnergyAlert)
            Picker(selection: $rightClick) {
                ForEach(RightClickAction.allCases) { Text($0.title).tag($0.rawValue) }
            } label: { Label("Menubar Right Click", systemImage: "cursorarrow.click.2").font(.system(size: 13, weight: .semibold)) }
        }
        SettingsSection(title: "Popover", icon: "macwindow") {
            ToggleRow(title: "Power Flow", icon: "point.3.connected.trianglepath.dotted", isOn: $showPowerFlow)
            ToggleRow(title: "Power Mode", icon: "leaf", isOn: $showPowerMode)
            ToggleRow(title: "Apps Using Significant Energy", icon: "flame", isOn: $showEnergyApps)
            if showEnergyApps {
                ToggleRow(title: "Include Background Processes", icon: "gearshape.2", isOn: $showBackground)
                    .padding(.leading, 24)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            ToggleRow(title: "Specifications", icon: "info.circle", isOn: $showSpecs)
        }
        SettingsSection(title: "Other", icon: "ellipsis.circle") {
            ToggleRow(title: "MagSafe LED: Indicate Charge Limit", icon: "light.beacon.max",
                      help: "Green at the limit, orange while charging or discharging toward it.", live: false, isOn: $magSafeLED)
            ToggleRow(title: "Blink Orange during Discharge", icon: "light.beacon.min", live: false, isOn: $magSafeBlink)
            Picker(selection: $magSafeMode) {
                Text("System").tag("system"); Text("Always Off").tag("off"); Text("Off During Sleep").tag("sleep")
            } label: { Label("LED Setting", systemImage: "lightbulb").font(.system(size: 13, weight: .semibold)) }
        }
    }
}

// MARK: - General

private struct GeneralPage: View {
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var confirmReset = false

    var body: some View {
        SettingsSection(title: "General", icon: "gearshape") {
            ToggleRow(title: "Launch at Login", icon: "power", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }
        }
        SettingsSection(title: "Help & Support", icon: "questionmark.circle") {
            HStack {
                Text("Source code, issues and release notes").font(.system(size: 13))
                Spacer()
                Link("Open on GitHub", destination: URL(string: "https://github.com/mks909/Stracotto")!).buttonStyle(.glass)
            }
        }
        SettingsSection(title: "Reset", icon: "arrow.counterclockwise") {
            HStack {
                Text("Restore every setting to its default. Your charge limit in macOS is left as is.").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button("Reset Settings…", role: .destructive) { confirmReset = true }.buttonStyle(.glass)
            }
            .confirmationDialog("Reset all Stracotto settings?", isPresented: $confirmReset) {
                Button("Reset", role: .destructive) {
                    if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
                }
            }
        }
    }
}

/// Wraps chips onto as many lines as needed.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? .infinity, subviews).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in arrange(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], size: CGSize) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width { x = 0; y += row + spacing; row = 0 }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing; row = max(row, size.height); maxX = max(maxX, x)
        }
        return (points, CGSize(width: maxX - spacing, height: y + row))
    }
}
