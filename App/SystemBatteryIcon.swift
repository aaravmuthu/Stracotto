import AppKit

/// Stracotto's battery is meant to stand in for macOS's own. macOS keeps its battery item's visibility and position in
/// Control Center's preferences; Stracotto reads them (never writes them) and points the user to the switch.
enum SystemBatteryIcon {
    private static let autosaveName = "StracottoBattery"
    private static let controlCenter = "com.apple.controlcenter"

    /// Whether macOS's own battery icon is currently in the menu bar.
    static var isShown: Bool {
        let value = CFPreferencesCopyValue("NSStatusItem Visible Battery" as CFString, controlCenter as CFString,
                                           kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool
        return value ?? true
    }

    /// The Control Center pane with the battery's "Show in Menu Bar" switch.
    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!)
    }

    /// Creates the status item in the slot macOS's battery uses, the first time only; after that the user's own
    /// ⌘-drag placement wins.
    @MainActor static func makeStatusItem() -> NSStatusItem {
        let key = "NSStatusItem Preferred Position \(autosaveName)"
        if UserDefaults.standard.object(forKey: key) == nil,
           let applePosition = CFPreferencesCopyValue("NSStatusItem Preferred Position Battery" as CFString, controlCenter as CFString,
                                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Double {
            UserDefaults.standard.set(applePosition, forKey: key)
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = autosaveName
        return item
    }
}
