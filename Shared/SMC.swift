import Foundation
import IOKit

/// Read-only access to the AppleSMC user client. Reads work as any user, so the app never needs root.
///
/// Layout mirrors the kernel's SMCParamStruct (80 bytes). Swift packs a trailing UInt8 without padding,
/// so KeyInfo carries explicit pad bytes to keep `result` at offset 40 like the C struct.
final class SMC: @unchecked Sendable {
    enum SMCError: Error, CustomStringConvertible {
        case serviceNotFound, openFailed(kern_return_t), call(kern_return_t), smc(UInt8)
        var description: String {
            switch self {
            case .serviceNotFound: "AppleSMC service not found"
            case .openFailed(let r): "IOServiceOpen failed 0x\(String(UInt32(bitPattern: r), radix: 16))"
            case .call(let r): "SMC call failed 0x\(String(UInt32(bitPattern: r), radix: 16))"
            case .smc(let c): c == 132 ? "SMC key not found" : "SMC error \(c)"
            }
        }
    }

    struct KeyInfo: Sendable { let size: Int; let type: String }

    private struct Version { var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0, release: UInt16 = 0 }
    private struct PLimit { var version: UInt16 = 0, length: UInt16 = 0, cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0 }
    private struct Info { var dataSize: UInt32 = 0, dataType: UInt32 = 0, dataAttributes: UInt8 = 0, pad: (UInt8, UInt8, UInt8) = (0, 0, 0) }
    private struct Param {
        var key: UInt32 = 0
        var version = Version()
        var pLimit = PLimit()
        var info = Info()
        var result: UInt8 = 0, status: UInt8 = 0, selector: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }

    private enum Selector: UInt8 { case read = 5, keyInfo = 9 }

    static let shared = try? SMC()

    private let connection: io_connect_t
    private let lock = NSLock()

    init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.serviceNotFound }
        defer { IOObjectRelease(service) }
        var conn: io_connect_t = 0
        let r = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard r == kIOReturnSuccess else { throw SMCError.openFailed(r) }
        connection = conn
    }

    deinit { IOServiceClose(connection) }

    private func call(_ input: Param) throws -> Param {
        assert(MemoryLayout<Param>.stride == 80)
        var input = input, output = Param()
        var outSize = MemoryLayout<Param>.stride
        let r = lock.withLock {
            IOConnectCallStructMethod(connection, 2, &input, MemoryLayout<Param>.stride, &output, &outSize)
        }
        guard r == kIOReturnSuccess else { throw SMCError.call(r) }
        guard output.result == 0 else { throw SMCError.smc(output.result) }
        return output
    }

    func info(_ key: String) throws -> KeyInfo {
        var p = Param(); p.key = key.fourCharCode; p.selector = Selector.keyInfo.rawValue
        let o = try call(p)
        return KeyInfo(size: Int(o.info.dataSize), type: o.info.dataType.fourCharString)
    }

    func read(_ key: String) throws -> [UInt8] {
        let i = try info(key)
        var p = Param(); p.key = key.fourCharCode; p.info.dataSize = UInt32(i.size); p.selector = Selector.read.rawValue
        let o = try call(p)
        return withUnsafeBytes(of: o.bytes) { Array($0.prefix(i.size)) }
    }


    func exists(_ key: String) -> Bool { (try? info(key)) != nil }

    /// Decodes the common numeric SMC types to Double. Apple silicon stores flt little-endian, integers little-endian.
    func number(_ key: String) -> Double? {
        guard let i = try? info(key), let b = try? read(key) else { return nil }
        switch i.type {
        case "flt ": return b.count == 4 ? Double(Float(bitPattern: UInt32(littleEndian: b.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }))) : nil
        case "ui8 ": return Double(b[0])
        case "hex_" where b.count == 1: return Double(b[0])
        case "si8 ": return Double(Int8(bitPattern: b[0]))
        case "ui16": return Double(b.withUnsafeBytes { $0.loadUnaligned(as: UInt16.self) })
        case "si16": return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Int16.self) })
        case "ui32": return Double(b.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) })
        case "si32": return Double(b.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) })
        default: return nil
        }
    }
}

extension String {
    var fourCharCode: UInt32 { utf8.reduce(0) { $0 << 8 | UInt32($1) } }
}

extension UInt32 {
    var fourCharString: String { String(bytes: [24, 16, 8, 0].map { UInt8((self >> $0) & 0xff) }, encoding: .ascii) ?? "????" }
}
