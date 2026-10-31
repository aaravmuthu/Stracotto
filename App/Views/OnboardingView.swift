import SwiftUI

/// The welcome that opens the first time Stracotto launches: five short pages, each doing one real piece of setup
/// (charge limit, menu bar spot, launch at login). Nothing changes until the person taps; the window is torn down on
/// close, so none of its motion keeps running afterwards.
struct OnboardingView: View {
    static let pageCount = 5

    var initialPage = 0
    /// Snapshots draw the settled state; the live window plays its entrance.
    var settled = false
    var onFinish: () -> Void = {}

    @Environment(BatteryMonitor.self) private var battery
    @Environment(ChargeController.self) private var charge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(Prefs.menuBarEnergyAlert) private var energyAlert = true
    @State private var page: Int
    @State private var forward = true
    @State private var chosenLimit = 80
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var appleIconShown = SystemBatteryIcon.isShown

    private static let ember = Color(red: 1.0, green: 0.55, blue: 0.18)

    init(initialPage: Int = 0, settled: Bool = false, onFinish: @escaping () -> Void = {}) {
        self.initialPage = initialPage
        self.settled = settled
        self.onFinish = onFinish
        _page = State(initialValue: initialPage)
    }

    var body: some View {
        ZStack {
            background
            VStack(spacing: 0) {
                ZStack {
                    pageContent
                        .id(page)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .offset(x: forward ? 70 : -70).combined(with: .opacity),
                            removal: .offset(x: forward ? -70 : 70).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer
            }
        }
        .frame(width: 560, height: 600)
        .environment(\.colorScheme, .dark)
        .onAppear { chosenLimit = charge.limit }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            appleIconShown = SystemBatteryIcon.isShown
        }
    }

    // MARK: - Chrome

    private var background: some View {
        ZStack {
            Theme.backdrop
            RadialGradient(colors: [Self.ember.opacity(0.22), .clear], center: .init(x: 0.5, y: 0.0), startRadius: 0, endRadius: 380)
            RadialGradient(colors: [Theme.charging.opacity(0.10), .clear], center: .init(x: 0.9, y: 1.0), startRadius: 0, endRadius: 320)
        }
        .ignoresSafeArea()
    }

    private var footer: some View {
        HStack {
            Button { go(page - 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold)).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .liquidGlass(interactive: true, in: .circle)
            .opacity(page == 0 ? 0 : 1)
            .disabled(page == 0)

            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<Self.pageCount, id: \.self) { i in
                    Capsule().fill(.white.opacity(i == page ? 0.9 : 0.25))
                        .frame(width: i == page ? 20 : 7, height: 7)
                }
            }
            .animation(.smooth(duration: 0.35), value: page)
            Spacer()

            Button(action: advance) {
                Text(primaryTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 22)
                    .frame(height: 40)
                    .contentTransition(.interpolate)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
            .liquidGlass(tint: Self.ember.opacity(0.55), interactive: true, in: .capsule)
            .animation(.smooth(duration: 0.3), value: primaryTitle)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 26)
        .padding(.top, 8)
    }

    private var primaryTitle: String {
        switch page {
        case 0: "Get Started"
        case 1: chosenLimit == charge.limit || charge.backendStatus != .ready ? "Continue" : "Set Limit to \(chosenLimit)%"
        case Self.pageCount - 1: "Start Using Stracotto"
        default: "Continue"
        }
    }

    private func advance() {
        if page == 1, charge.backendStatus == .ready, chosenLimit != charge.limit { charge.limit = chosenLimit }
        if page == Self.pageCount - 1 { onFinish() } else { go(page + 1) }
    }

    private func go(_ next: Int) {
        guard next >= 0, next < Self.pageCount else { return }
        forward = next > page
        withAnimation(.smooth(duration: 0.5)) { page = next }
    }

    // MARK: - Pages

    @ViewBuilder private var pageContent: some View {
        switch page {
        case 0: welcome
        case 1: chargeLimit
        case 2: powerFlow
        case 3: menuBar
        default: finish
        }
    }

    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center)
                .modifier(Reveal(delay: 0.05, settled: settled))
            Text(subtitle).font(.system(size: 14.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .frame(maxWidth: 400)
                .modifier(Reveal(delay: 0.15, settled: settled))
        }
    }

    private var welcome: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            ZStack {
                if !reduceMotion && !settled { PulsingImage(image: Self.glow, period: 3.6, scale: 1.2, dim: 0.5).frame(width: 330, height: 330) }
                else { Image(nsImage: Self.glow).resizable().frame(width: 330, height: 330).opacity(0.8) }
                AppIconArt().frame(width: 168, height: 168)
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 10)
                    .modifier(Pop(settled: settled))
            }
            .frame(height: 190)
            VStack(spacing: 10) {
                Text("Stracotto").font(.system(size: 40, weight: .bold))
                    .modifier(Reveal(delay: 0.35, settled: settled))
                Text("Slow-cooked battery care for your Mac.")
                    .font(.system(size: 16)).foregroundStyle(.secondary)
                    .modifier(Reveal(delay: 0.5, settled: settled))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }

    private var chargeLimit: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            heading("Pick where charging stops",
                    "Holding your battery below 100% keeps it healthy for years longer. You can change this any time.")
            VStack(spacing: 18) {
                BatteryBar(percent: battery.snapshot.percent, state: battery.snapshot.state, height: 34, limit: chosenLimit,
                           allowedLimits: charge.allowedLimits, onLimitChange: { chosenLimit = $0 })
                HStack(spacing: 8) {
                    ForEach(charge.allowedLimits, id: \.self) { value in
                        Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) { chosenLimit = value } } label: {
                            Text("\(value)%").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                                .frame(width: 58, height: 32)
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(tint: chosenLimit == value ? Self.ember.opacity(0.5) : nil, interactive: true, in: .capsule)
                    }
                }
                if charge.backendStatus != .ready {
                    Text("This Mac doesn't expose a charge limit, so Stracotto will just monitor.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Text(chosenLimit == 100 ? "No limit: the battery charges fully, as macOS does by default."
                         : "Charging pauses at \(chosenLimit)%. Top Up in the menu bar tops you off to 100% when you need it.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 380)
                }
            }
            .padding(.horizontal, 44)
            .modifier(Reveal(delay: 0.25, settled: settled))
            Spacer(minLength: 0)
        }
    }

    private var powerFlow: some View {
        let sample = Snapshots.sampleStates().first { $0.0 == "charging" }!.1
        return VStack(spacing: 26) {
            Spacer(minLength: 0)
            heading("See where every watt goes",
                    "Power Flow follows energy from the charger through the battery and into your chip, graphics and display.")
            PowerFlowView(flow: sample.flow, state: .charging, adapterWatts: 36, height: 181)
                .padding(.horizontal, 44)
                .modifier(Reveal(delay: 0.25, settled: settled))
            Text("Tap any block for details. Apps that burn a lot of power show up by name.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .modifier(Reveal(delay: 0.4, settled: settled))
            Spacer(minLength: 0)
        }
    }

    private var menuBar: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            heading("Look up to the menu bar",
                    "Stracotto lives next to the clock. Click it any time for the charge bar, Power Flow and Top Up.")
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    Image(systemName: "wifi"); Image(systemName: "magnifyingglass")
                    MenuBarIcon()
                        .environment(BatteryMonitor(fixed: battery.snapshot))
                        .environment(EnergyMonitor(fixed: []))
                    Text("Fri 9:41").font(.system(size: 12, weight: .medium))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 16).frame(height: 30)
                .background(.black.opacity(0.55), in: .capsule)
                .overlay { Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1) }
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold)).foregroundStyle(Self.ember)
                    .offset(x: -52)
                Text("This is Stracotto").font(.system(size: 12, weight: .semibold)).foregroundStyle(Self.ember)
                    .offset(x: -52)
            }
            .modifier(Reveal(delay: 0.25, settled: settled))

            Group {
                if appleIconShown {
                    VStack(spacing: 10) {
                        Text("macOS is still showing its own battery icon. Hide it so Stracotto takes its spot.")
                            .font(.system(size: 12.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                        Button { SystemBatteryIcon.openSettings() } label: {
                            Text("Hide it in System Settings").font(.system(size: 13, weight: .semibold))
                                .padding(.horizontal, 18).frame(height: 34)
                        }
                        .buttonStyle(.plain)
                        .liquidGlass(interactive: true, in: .capsule)
                    }
                } else {
                    Label("macOS's own battery icon is hidden. Stracotto has its spot.", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.charging)
                }
            }
            .modifier(Reveal(delay: 0.4, settled: settled))
            Spacer(minLength: 0)
        }
    }

    private var finish: some View {
        VStack(spacing: 26) {
            Spacer(minLength: 0)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64)).foregroundStyle(LinearGradient(colors: [Theme.bolt, Self.ember], startPoint: .top, endPoint: .bottom))
                .symbolEffect(.bounce, options: .nonRepeating, value: page == Self.pageCount - 1)
                .modifier(Pop(settled: settled))
            heading("You're all set", "Stracotto is quietly watching your battery. Two last choices:")
            VStack(spacing: 10) {
                toggleRow("Open at login", "Starts with your Mac, so the limit is always enforced.", "power", $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in LaunchAtLogin.set(on) }
                toggleRow("Warn me about hungry apps", "A flame appears in the menu bar when one drains your battery.", "flame.fill", $energyAlert)
            }
            .padding(.horizontal, 44)
            .modifier(Reveal(delay: 0.3, settled: settled))
            Spacer(minLength: 0)
        }
    }

    private func toggleRow(_ title: String, _ detail: String, _ symbol: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold)).foregroundStyle(Self.ember).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if settled {
                // Offscreen renders can't draw AppKit's switch; this is the same shape.
                Capsule().fill(isOn.wrappedValue ? Theme.charging : .white.opacity(0.2)).frame(width: 38, height: 22)
                    .overlay(alignment: isOn.wrappedValue ? .trailing : .leading) { Circle().fill(.white).padding(2) }
            } else {
                Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .liquidGlass(in: .rect(cornerRadius: 18, style: .continuous))
    }

    @MainActor private static let glow: NSImage = {
        let view = RadialGradient(colors: [Color(red: 1.0, green: 0.55, blue: 0.18).opacity(0.5), .clear], center: .center, startRadius: 0, endRadius: 165)
            .frame(width: 330, height: 330)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        return renderer.nsImage ?? NSImage()
    }()
}

/// Fades and lifts into place after a delay.
private struct Reveal: ViewModifier {
    let delay: Double
    let settled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || settled ? 1 : 0)
            .offset(y: shown || settled || reduceMotion ? 0 : 14)
            .onAppear {
                guard !settled else { return }
                withAnimation(.smooth(duration: 0.7).delay(reduceMotion ? 0 : delay)) { shown = true }
            }
    }
}

/// Springs up from small, with a slight settle.
private struct Pop: ViewModifier {
    let settled: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(shown || settled || reduceMotion ? 1 : 0.55)
            .rotationEffect(.degrees(shown || settled || reduceMotion ? 0 : -9))
            .opacity(shown || settled ? 1 : 0)
            .onAppear {
                guard !settled else { return }
                withAnimation(.spring(response: 0.7, dampingFraction: 0.62).delay(0.1)) { shown = true }
            }
    }
}
