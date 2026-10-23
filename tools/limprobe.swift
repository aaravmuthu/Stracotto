import Foundation
setvbuf(stdout, nil, _IONBF, 0)
let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW)
typealias Copy0 = @convention(c) () -> Unmanaged<CFTypeRef>?
typealias CopyOut = @convention(c) (UnsafeMutablePointer<Unmanaged<CFTypeRef>?>) -> Int32
let limits = unsafeBitCast(dlsym(h, "IOPSCopyBatteryLevelLimits")!, to: Copy0.self)
print("IOPSCopyBatteryLevelLimits →", limits()?.takeRetainedValue() ?? "nil" as CFString)
var out: Unmanaged<CFTypeRef>?
let status = unsafeBitCast(dlsym(h, "IOPSCopyChargeStatus")!, to: CopyOut.self)
let r = status(&out)
print("IOPSCopyChargeStatus ret=0x\(String(UInt32(bitPattern: r), radix: 16)) →", out?.takeRetainedValue() ?? "nil" as CFString)
