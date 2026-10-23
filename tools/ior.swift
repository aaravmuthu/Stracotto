import Foundation
typealias CopyChannels = @convention(c) (CFString, CFString?, UInt64, UInt64, UInt64) -> Unmanaged<CFMutableDictionary>?
typealias CreateSub = @convention(c) (UnsafeRawPointer?, CFMutableDictionary, UnsafeMutablePointer<Unmanaged<CFMutableDictionary>?>, UInt64, CFTypeRef?) -> OpaquePointer?
typealias CreateSamples = @convention(c) (OpaquePointer, CFMutableDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias SamplesDelta = @convention(c) (CFDictionary, CFDictionary, CFTypeRef?) -> Unmanaged<CFDictionary>?
typealias GetInt = @convention(c) (CFDictionary, Int32) -> Int64
typealias GetStr = @convention(c) (CFDictionary) -> Unmanaged<CFString>?
let h = dlopen("/usr/lib/libIOReport.dylib", RTLD_NOW)!
func f<T>(_ n: String, _ t: T.Type) -> T { unsafeBitCast(dlsym(h, n)!, to: t) }
let copy = f("IOReportCopyChannelsInGroup", CopyChannels.self)
let sub = f("IOReportCreateSubscription", CreateSub.self)
let samples = f("IOReportCreateSamples", CreateSamples.self)
let delta = f("IOReportCreateSamplesDelta", SamplesDelta.self)
let getInt = f("IOReportSimpleGetIntegerValue", GetInt.self)
let name = f("IOReportChannelGetChannelName", GetStr.self)
let unit = f("IOReportChannelGetUnitLabel", GetStr.self)
let chans = copy("Energy Model" as CFString, nil, 0, 0, 0)!.takeRetainedValue()
var subbed: Unmanaged<CFMutableDictionary>?
let s = sub(nil, chans, &subbed, 0, nil)!
let sc = subbed!.takeRetainedValue()
let a = samples(s, sc, nil)!.takeRetainedValue()
Thread.sleep(forTimeInterval: 3)
let b = samples(s, sc, nil)!.takeRetainedValue()
let d = delta(a, b, nil)!.takeRetainedValue() as NSDictionary
var total = 0.0
for c in d["IOReportChannels"] as! [NSDictionary] {
  let n = name(c)!.takeUnretainedValue() as String; let u = (unit(c)?.takeUnretainedValue() as String?) ?? ""
  let v = Double(getInt(c, 0)) / 3; let w = v / (u == "mJ" ? 1e3 : u == "uJ" ? 1e6 : u == "nJ" ? 1e9 : 1)
  if true { print(String(format: "%-28@ %7.3f W (%@)", n as NSString, w, u as NSString)) }
}
