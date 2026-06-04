import Foundation
import IOKit

public struct SMCSnapshot: Equatable, Sendable {
    public var fans: [FanReading]
    public var thermals: [ThermalReading]
    public var warnings: [String]
}

public final class SMCSensorProvider: @unchecked Sendable {
    private let reader: SMCReading
    private let thermalLock = NSLock()
    private var lastStableThermals: [String: Double] = [:]

    public init(reader: SMCReading = AppleSMCReader()) {
        self.reader = reader
    }

    public func readSensors() -> SMCSnapshot {
        guard let fanCount = reader.numericValue(forKey: "FNum"), fanCount > 0 else {
            return SMCSnapshot(fans: [], thermals: readThermals(), warnings: [])
        }

        let fans = (0..<Int(fanCount)).map { index in
            FanReading(
                id: "fan-\(index)",
                name: reader.stringValue(forKey: "F\(index)ID") ?? "Fan \(index + 1)",
                currentRPM: reader.numericValue(forKey: "F\(index)Ac"),
                minRPM: reader.numericValue(forKey: "F\(index)Mn"),
                maxRPM: reader.numericValue(forKey: "F\(index)Mx")
            )
        }

        return SMCSnapshot(fans: fans, thermals: readThermals(), warnings: [])
    }

    private func readThermals() -> [ThermalReading] {
        let candidates = [
            ("CPU Proximity", "TC0P"),
            ("CPU Core 1", "TC0E"),
            ("CPU Core 2", "TC0F"),
            ("SoC", "Tp09"),
            ("Die", "Te05")
        ]

        let rawValues: [String: (String, Double)] = Dictionary(uniqueKeysWithValues: candidates.compactMap { label, key in
            guard let value = reader.numericValue(forKey: key), value > -100, value < 150 else {
                return nil as (String, (String, Double))?
            }
            return (key, (label, value))
        })

        let stableDie = rawValues["Te05"]?.1

        thermalLock.lock()
        defer { thermalLock.unlock() }

        return candidates.compactMap { label, key in
            guard let raw = rawValues[key]?.1 else {
                return nil
            }

            let value = stableThermalValue(raw: raw, key: key, stableDie: stableDie)
            guard let value else {
                return nil
            }

            lastStableThermals[key] = value
            return ThermalReading(label: label, celsius: value, source: "SMC \(key)")
        }
    }

    private func stableThermalValue(raw: Double, key: String, stableDie: Double?) -> Double? {
        guard raw >= 15, raw <= 115 else {
            return lastStableThermals[key]
        }

        if key == "Tp09", let stableDie, stableDie >= 55, raw < stableDie - 30 {
            return lastStableThermals[key]
        }

        if let last = lastStableThermals[key], abs(raw - last) > 35 {
            return last
        }

        return raw
    }
}

public protocol SMCReading: Sendable {
    func numericValue(forKey key: String) -> Double?
    func stringValue(forKey key: String) -> String?
}

public final class FixtureSMCReader: SMCReading, @unchecked Sendable {
    private let values: [String: Double]
    private let strings: [String: String]

    public init(values: [String: Double], strings: [String: String] = [:]) {
        self.values = values
        self.strings = strings
    }

    public func numericValue(forKey key: String) -> Double? {
        values[key]
    }

    public func stringValue(forKey key: String) -> String? {
        strings[key]
    }
}

public final class AppleSMCReader: SMCReading, @unchecked Sendable {
    private let connection: io_connect_t
    private let isAvailable: Bool

    public init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            connection = 0
            isAvailable = false
            return
        }

        var openedConnection: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &openedConnection)
        IOObjectRelease(service)

        connection = openedConnection
        isAvailable = result == kIOReturnSuccess
    }

    deinit {
        if isAvailable {
            IOServiceClose(connection)
        }
    }

    public func numericValue(forKey key: String) -> Double? {
        guard let data = readData(forKey: key) else {
            return nil
        }

        return decodeNumeric(data: data)
    }

    public func stringValue(forKey key: String) -> String? {
        guard let data = readData(forKey: key) else {
            return nil
        }

        let bytes = data.bytes.prefix { $0 != 0 }
        let value = String(bytes: bytes, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : nil
    }

    public func debugValue(forKey key: String) -> String {
        guard let data = readData(forKey: key) else {
            return "nil"
        }
        let bytes = data.bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
        return "type=\(data.dataType) size=\(data.dataSize) bytes=[\(bytes)]"
    }

    private func readData(forKey key: String) -> SMCVal? {
        guard isAvailable else {
            return nil
        }

        let keyCode = fourCharCode(key)
        var infoInput = SMCParamStruct()
        infoInput.key = keyCode
        infoInput.data8 = SMCCommand.readKeyInfo.rawValue

        guard let infoOutput = call(input: infoInput), infoOutput.result == 0 else {
            return nil
        }

        var readInput = SMCParamStruct()
        readInput.key = keyCode
        readInput.keyInfo = infoOutput.keyInfo
        readInput.data8 = SMCCommand.readBytes.rawValue

        guard let readOutput = call(input: readInput), readOutput.result == 0 else {
            return nil
        }

        return SMCVal(
            key: key,
            dataSize: Int(infoOutput.keyInfo.dataSize),
            dataType: stringFromFourCharCode(infoOutput.keyInfo.dataType),
            bytes: Array(readOutput.bytesArray.prefix(Int(infoOutput.keyInfo.dataSize)))
        )
    }

    private func call(input: SMCParamStruct) -> SMCParamStruct? {
        var input = input
        var output = SMCParamStruct()
        let inputSize = MemoryLayout<SMCParamStruct>.stride
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = withUnsafeMutablePointer(to: &input) { inputPointer in
            withUnsafeMutablePointer(to: &output) { outputPointer in
                IOConnectCallStructMethod(
                    connection,
                    2,
                    inputPointer,
                    inputSize,
                    outputPointer,
                    &outputSize
                )
            }
        }

        guard result == kIOReturnSuccess else {
            return nil
        }
        return output
    }
}

public struct SMCVal: Equatable, Sendable {
    public var key: String
    public var dataSize: Int
    public var dataType: String
    public var bytes: [UInt8]

    public init(key: String, dataSize: Int, dataType: String, bytes: [UInt8]) {
        self.key = key
        self.dataSize = dataSize
        self.dataType = dataType
        self.bytes = bytes
    }
}

public func decodeNumeric(data: SMCVal) -> Double? {
    switch data.dataType {
    case "flt ":
        guard data.bytes.count >= 4 else { return nil }
        let bits = UInt32(data.bytes[0]) | UInt32(data.bytes[1]) << 8 | UInt32(data.bytes[2]) << 16 | UInt32(data.bytes[3]) << 24
        return Double(Float(bitPattern: bits))
    case "fpe2":
        guard data.bytes.count >= 2 else { return nil }
        let raw = UInt16(data.bytes[0]) << 8 | UInt16(data.bytes[1])
        return Double(raw) / 4.0
    case "sp78":
        guard data.bytes.count >= 2 else { return nil }
        let raw = Int16(bitPattern: UInt16(data.bytes[0]) << 8 | UInt16(data.bytes[1]))
        return Double(raw) / 256.0
    case "ui8 ":
        guard let value = data.bytes.first else { return nil }
        return Double(value)
    case "ui16":
        guard data.bytes.count >= 2 else { return nil }
        return Double(UInt16(data.bytes[0]) << 8 | UInt16(data.bytes[1]))
    case "ui32":
        guard data.bytes.count >= 4 else { return nil }
        let raw = UInt32(data.bytes[0]) << 24 | UInt32(data.bytes[1]) << 16 | UInt32(data.bytes[2]) << 8 | UInt32(data.bytes[3])
        return Double(raw)
    default:
        return nil
    }
}

private enum SMCCommand: UInt8 {
    case readBytes = 5
    case readKeyInfo = 9
}

private struct SMCKeyInfoData {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCParamStruct {
    typealias Bytes32 = (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    )

    struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    struct PLimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    var key: UInt32 = 0
    var vers = Version()
    var pLimitData = PLimitData()
    var keyInfo = SMCKeyInfoData()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: Bytes32 = (
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
        UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0)
    )
}

private func fourCharCode(_ string: String) -> UInt32 {
    string.utf8.prefix(4).reduce(UInt32(0)) { ($0 << 8) + UInt32($1) }
}

private func stringFromFourCharCode(_ code: UInt32) -> String {
    let bytes = [
        UInt8((code >> 24) & 0xff),
        UInt8((code >> 16) & 0xff),
        UInt8((code >> 8) & 0xff),
        UInt8(code & 0xff)
    ]
    return String(bytes: bytes, encoding: .macOSRoman) ?? ""
}

private extension SMCParamStruct {
    var bytesArray: [UInt8] {
        Mirror(reflecting: bytes).children.compactMap { $0.value as? UInt8 }
    }
}
