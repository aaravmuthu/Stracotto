import AppKit
import Observation
import SwiftUI
import Sparkle

/// Self-updates through Sparkle. Updates are only installed when their EdDSA signature matches the `SUPublicEDKey` in
/// Info.plist, so a hijacked feed or download can't push code. Checks once a day (`SUScheduledCheckInterval`), a single
/// small request, and never while the app is otherwise idle for longer than that.
@MainActor @Observable
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private(set) var canCheck = false
    var automaticChecks: Bool {
        didSet { controller?.updater.automaticallyChecksForUpdates = automaticChecks }
    }

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var observation: NSKeyValueObservation?

    override init() {
        automaticChecks = true
        super.init()
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        automaticChecks = controller.updater.automaticallyChecksForUpdates
        canCheck = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates) { [weak self] updater, _ in
            let can = updater.canCheckForUpdates
            DispatchQueue.main.async { self?.canCheck = can }
        }
    }

    /// Previews and snapshots: never touches the network.
    init(inert: Void) {
        automaticChecks = true
        super.init()
    }

    var versionText: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    // MARK: - SPUUpdaterDelegate

    /// Test hook: point a build at a local feed. Installs still have to carry a valid EdDSA signature.
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment["STRACOTTO_FEED_URL"]
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// A menu bar app has no Dock icon to bounce, so an alert for a background check would open behind other windows.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard handleShowingUpdate else { return }
        DispatchQueue.main.async { NSApp.activate() }
    }
}

extension EnvironmentValues {
    @Entry var updater: Updater? = nil
}
