import Foundation
import CoreGraphics
import Darwin
import IOKit

/// Readings for the consumers that macOS doesn't report in watts without root. Both are cheap, unprivileged reads.
enum PowerSources {
    // MARK: - Display

    private typealias GetBrightness = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private static let getBrightness: GetBrightness? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY),
              let symbol = dlsym(handle, "DisplayServicesGetBrightness") else { return nil }
        return unsafeBitCast(symbol, to: GetBrightness.self)
    }()

    /// Backlight level 0…1 of the built-in display; nil when there isn't one (lid closed, external only).
    static func brightness() -> Double? {
        guard let getBrightness else { return nil }
        var level: Float = -1
        let id = CGMainDisplayID()
        guard CGDisplayIsBuiltin(id) != 0, getBrightness(id, &level) == 0, level >= 0 else { return nil }
        return Double(level)
    }

    /// A MacBook panel's draw is the backlight, which grows faster than linearly with brightness: roughly 0.4 W at the
    /// dimmest, ~3 W at 65 % and 5-6 W at full SDR. An estimate (macOS has no display power sensor), and labelled so.
    static func displayWatts(brightness b: Double) -> Double { 0.4 + 5.2 * pow(b, 1.6) }

    // MARK: - GPU

    /// GPU busy share 0…1 from the accelerator's own statistics.
    static func gpuUtilization() -> Double? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: Double?
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let stats = IORegistryEntryCreateCFProperty(service, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any],
                  let percent = (stats["Device Utilization %"] as? NSNumber)?.doubleValue else { continue }
            best = max(best ?? 0, percent / 100)
        }
        return best
    }

    /// Splits the SoC's measured package power (CPU + GPU + Neural Engine) into CPU and GPU by GPU busy share.
    static func splitSoC(_ soc: Double, gpuUtilization u: Double) -> (cpu: Double, gpu: Double) {
        let gpu = min(soc * 0.6 * u, max(soc - 0.3, 0))
        return (soc - gpu, gpu)
    }
}
