import AppKit
import Observation

/// Charge limit and Top Up, backed by macOS's own Maximum Charge Limit (see `MCLClient`). The limit stays in sync with
/// System Settings in both directions. Features MCL can't express (sailing, heat protection, below-80% limits…) are
/// remembered but not enforced yet.
@MainActor @Observable
final class ChargeController {
    /// What the hardware path accepts; the slider snaps to these.
    let allowedLimits: [Int]
    var limitRange: ClosedRange<Int> { (allowedLimits.first ?? 80)...(allowedLimits.last ?? 100) }

    var limit: Int {
        didSet {
            guard limit != oldValue else { return }
            UserDefaults.standard.set(limit, forKey: Prefs.chargeLimit)
            apply()
        }
    }
    var isToppingUp = false {
        didSet { if isToppingUp != oldValue { apply() } }
    }

    /// What the battery is actually being held at right now.
    var target: Int { isToppingUp ? 100 : limit }

    private(set) var backendStatus: BackendStatus

    enum BackendStatus: Equatable {
        case ready
        case unavailable(String)
    }

    private let mcl = MCLClient.shared
    private var syncing = false

    init() {
        allowedLimits = mcl.availableLimits
        if mcl.isSupported {
            backendStatus = .ready
            limit = mcl.isEnabled ? (mcl.limit ?? 80) : 100
        } else {
            backendStatus = .unavailable("This Mac doesn't support macOS's charge limit")
            let stored = UserDefaults.standard.integer(forKey: Prefs.chargeLimit)
            limit = stored > 0 ? stored : 80
        }
        observeSystemChanges()
    }

    /// For snapshots and docs: a fixed limit that never reads or writes the Mac's real charge limit.
    init(previewLimit: Int) {
        allowedLimits = [80, 85, 90, 95, 100]
        backendStatus = .ready
        limit = previewLimit
    }

    /// Nearest value the hardware accepts, for the slider's drag.
    func snapped(_ value: Int) -> Int {
        allowedLimits.min { abs($0 - value) < abs($1 - value) } ?? value
    }

    func toggleTopUp() { isToppingUp.toggle() }

    /// Top Up ends when the charger is removed, like AlDente.
    func batteryChanged(_ snapshot: BatterySnapshot) {
        if isToppingUp && !snapshot.isPluggedIn { isToppingUp = false }
    }

    private func apply() {
        guard backendStatus == .ready, !syncing else { return }
        if isToppingUp {
            mcl.overrideTarget(100)
        } else if limit >= 100 {
            mcl.disable()
        } else {
            if !mcl.isEnabled { mcl.enable() }
            mcl.setLimit(snapped(limit))
        }
    }

    /// Picks up changes made in System Settings (or by macOS itself) so the slider never lies.
    private func observeSystemChanges() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(center, observer, { _, observer, _, _, _ in
            guard let observer else { return }
            let controller = Unmanaged<ChargeController>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { controller.resync() } }
        }, MCLClient.changedNotification as CFString, nil, .deliverImmediately)
    }

    private func resync() {
        let systemLimit = mcl.isEnabled ? (mcl.limit ?? limit) : 100
        guard systemLimit != limit, !isToppingUp else { return }
        syncing = true
        limit = systemLimit
        syncing = false
    }
}
