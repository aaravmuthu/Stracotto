import Foundation
import IOKit

// Read-only SMC probe. Mirrors the AppleSMC user-client struct layout.
struct KeyDataVer { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
struct PLimitData { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
struct KeyInfo { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0; var pad: (UInt8,UInt8,UInt8) = (0,0,0) }
typealias Bytes32 = (UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,
                     UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8,UInt8)
struct KeyData {
    var key: UInt32 = 0
    var vers = KeyDataVer()
    var pLimitData = PLimitData()
    var keyInfo = KeyInfo()
    var result: UInt8 = 0, status: UInt8 = 0, data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes32 = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

func fourCC(_ s: String) -> UInt32 { s.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
func str(_ v: UInt32) -> String { String(bytes: [24,16,8,0].map { UInt8((v >> $0) & 0xff) }, encoding: .ascii) ?? "?" }

let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
var conn: io_connect_t = 0
guard IOServiceOpen(service, mach_task_self_, 0, &conn) == kIOReturnSuccess else { print("open failed"); exit(1) }

func call(_ input: inout KeyData) -> (kern_return_t, KeyData) {
    var output = KeyData()
    var outSize = MemoryLayout<KeyData>.stride
    let r = IOConnectCallStructMethod(conn, 2, &input, MemoryLayout<KeyData>.stride, &output, &outSize)
    return (r, output)
}

func read(_ key: String) -> String {
    var info = KeyData(); info.key = fourCC(key); info.data8 = 9 // kSMCGetKeyInfo
    let (r1, o1) = call(&info)
    guard r1 == kIOReturnSuccess, o1.result == 0 else { return "missing r=\(String(r1, radix: 16)) res=\(o1.result) stride=\(MemoryLayout<KeyData>.stride)" }
    var rd = KeyData(); rd.key = fourCC(key); rd.keyInfo.dataSize = o1.keyInfo.dataSize; rd.data8 = 5 // kSMCReadKey
    let (r2, o2) = call(&rd)
    guard r2 == kIOReturnSuccess, o2.result == 0 else { return "read err \(o2.result)" }
    let bytes = withUnsafeBytes(of: o2.bytes) { Array($0.prefix(Int(o1.keyInfo.dataSize))) }
    return "type=\(str(o1.keyInfo.dataType)) size=\(o1.keyInfo.dataSize) attr=0x\(String(o1.keyInfo.dataAttributes, radix: 16)) bytes=\(bytes.map { String(format: "%02x", $0) }.joined(separator: " "))"
}

let keys = CommandLine.arguments.count > 1 ? Array(CommandLine.arguments.dropFirst())
    : ["CHTE", "CH0B", "CH0C", "CHIE", "CH0I", "CH0J", "CH0K", "CHWA", "CHLS", "ACLC", "BCLM", "BCLF", "AC-W", "B0TE", "TB0T", "TB1T", "TB2T", "PSTR", "PDTR", "PPBR", "B0AC", "B0AV", "B0RM", "BUIC"]
if !CommandLine.arguments.contains("--all") { for k in keys { print(k.padding(toLength: 5, withPad: " ", startingAt: 0), read(k)) } }

if CommandLine.arguments.contains("--all") {
    var cnt = KeyData(); cnt.key = fourCC("#KEY"); cnt.keyInfo.dataSize = 4; cnt.data8 = 5
    let (_, c) = call(&cnt)
    let n = withUnsafeBytes(of: c.bytes) { $0.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
    print("total keys:", n)
    for i in 0..<n {
        var q = KeyData(); q.data8 = 8; q.data32 = i
        let (_, o) = call(&q)
        let k = str(o.key)
        let line = read(k); if let r = line.range(of: "attr=0x"), let a = UInt8(line[r.upperBound...].prefix(2), radix: 16), a & 0x40 != 0 { print(k.padding(toLength: 5, withPad: " ", startingAt: 0), line) }
    }
}
