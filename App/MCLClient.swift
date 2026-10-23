import Foundation
import ObjectiveC

/// macOS 27's built-in Maximum Charge Limit (System Settings → Battery → Charging), driven through PowerUI's
/// `PowerUISmartChargeClient`, the same client the Battery pane uses. Works as a normal user, no helper needed.
/// Apple only accepts 80…100 in steps of 5.
///
/// Verified on macOS 27.0.1 (M3 Air, Oct 2026): get/set round-trips, `availableChargeLimits` = [80, 85, 90, 95, 100].
final class MCLClient: @unchecked Sendable {
    static let shared = MCLClient()
    /// Posted by powerd/PowerUI whenever the limit changes, including from System Settings.
    static let changedNotification = "com.apple.powerui.mclstatuschanged"

    private let client: NSObject?

    private init() {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/PowerUI", RTLD_NOW) != nil,
              let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else { client = nil; return }
        typealias Init = @convention(c) (AnyObject, Selector, NSString) -> NSObject?
        let alloc = cls.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue()
        client = alloc.flatMap { Self.call($0, "initWithClientName:", as: Init.self)?($0, NSSelectorFromString("initWithClientName:"), "com.aaravmuthu.stracotto") }
    }

    var isSupported: Bool {
        typealias F = @convention(c) (AnyObject, Selector) -> Bool
        guard let client, let f = Self.call(client, "isMCLSupported", as: F.self) else { return false }
        return f(client, NSSelectorFromString("isMCLSupported"))
    }

    var isEnabled: Bool {
        typealias F = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> UInt64
        guard let client, let f = Self.call(client, "isMCLCurrentlyEnabled:", as: F.self) else { return false }
        return f(client, NSSelectorFromString("isMCLCurrentlyEnabled:"), nil) != 0
    }

    var limit: Int? {
        typealias F = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> UInt8
        guard let client, let f = Self.call(client, "getMCLLimitWithError:", as: F.self) else { return nil }
        var error: NSError?
        let value = f(client, NSSelectorFromString("getMCLLimitWithError:"), &error)
        return error == nil ? Int(value) : nil
    }

    var availableLimits: [Int] {
        typealias F = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> NSArray?
        guard let client, let f = Self.call(client, "availableChargeLimitsWithError:", as: F.self),
              let values = f(client, NSSelectorFromString("availableChargeLimitsWithError:"), nil) as? [NSNumber] else { return [80, 85, 90, 95, 100] }
        return values.map(\.intValue)
    }

    @discardableResult func setLimit(_ value: Int) -> Bool { sendByte("setMCLLimit:error:", value) }
    /// Charges past the limit to `value` until macOS resets it (unplug or a new limit), which is exactly Top Up.
    @discardableResult func overrideTarget(_ value: Int) -> Bool { sendByte("temporarilyOverrideMCLTargetSoC:error:", value) }
    @discardableResult func enable() -> Bool { sendVoid("enableMCL:") }
    @discardableResult func disable() -> Bool { sendVoid("disableMCL:") }

    private func sendByte(_ selector: String, _ value: Int) -> Bool {
        typealias F = @convention(c) (AnyObject, Selector, UInt8, UnsafeMutablePointer<NSError?>?) -> Bool
        guard let client, let f = Self.call(client, selector, as: F.self) else { return false }
        var error: NSError?
        return f(client, NSSelectorFromString(selector), UInt8(clamping: value), &error) && error == nil
    }

    private func sendVoid(_ selector: String) -> Bool {
        typealias F = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool
        guard let client, let f = Self.call(client, selector, as: F.self) else { return false }
        var error: NSError?
        return f(client, NSSelectorFromString(selector), &error) && error == nil
    }

    /// Looks up an instance method's implementation so it can be called with its real C signature
    /// (PowerUI returns raw bytes and BOOLs, which `perform(_:)` can't carry).
    private static func call<T>(_ object: AnyObject, _ selector: String, as: T.Type) -> T? {
        guard let method = class_getInstanceMethod(type(of: object), NSSelectorFromString(selector)) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: T.self)
    }
}
