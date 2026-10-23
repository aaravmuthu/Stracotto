import AppKit
import Observation

/// Charge limit, Top Up and the other AlDente controls. Holds the user's intent; a `ChargeBackend` turns it into
/// hardware state. Until the macOS 27 backend is verified the backend reports itself unavailable and nothing is written.
@MainActor @Observable
final class ChargeController {
    static let limitRange = 20...100

    var limit: Int {
        didSet { UserDefaults.standard.set(limit, forKey: Prefs.chargeLimit); apply() }
    }
    var isToppingUp = false {
        didSet { apply() }
    }

    /// What the battery is actually being held at right now.
    var target: Int { isToppingUp ? 100 : limit }

    private(set) var backendStatus: BackendStatus = .unavailable("Charge control isn't set up yet")

    enum BackendStatus: Equatable {
        case ready
        case unavailable(String)
    }

    init() {
        let stored = UserDefaults.standard.integer(forKey: Prefs.chargeLimit)
        limit = Self.limitRange.contains(stored) ? stored : 80
    }

    func toggleTopUp() { isToppingUp.toggle() }

    /// Top Up ends when the charger is removed, like AlDente.
    func batteryChanged(_ snapshot: BatterySnapshot) {
        if isToppingUp && !snapshot.isPluggedIn { isToppingUp = false }
    }

    private func apply() {
        guard backendStatus == .ready else { return }
        // Backend write goes here once the macOS 27 charge-inhibit path is confirmed (see SMC key CHLS).
    }
}
