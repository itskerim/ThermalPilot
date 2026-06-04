import FanUsageCore
import Foundation

enum Diagnostics {
    static func runIfRequested() {
        if CommandLine.arguments.contains("--qa-sample") {
            runQASample()
            exit(0)
        }

        if CommandLine.arguments.contains("--diagnose-sensors") {
            runSensorDiagnosis()
            exit(0)
        }
    }

    private static func runSensorDiagnosis() {
        let smc = SMCSensorProvider()
        let snapshot = smc.readSensors()
        print("Thermal Pilot sensor diagnosis")
        print("fans=\(snapshot.fans)")
        print("thermals=\(snapshot.thermals)")
        print("warnings=\(snapshot.warnings)")

        let reader = AppleSMCReader()
        let keys = [
            "FNum", "F0Ac", "F0Mn", "F0Mx", "F0ID",
            "F1Ac", "F1Mn", "F1Mx", "F1ID",
            "TC0P", "TC0E", "TC0F", "Tp09", "Te05"
        ]
        for key in keys {
            let number = reader.numericValue(forKey: key).map { String($0) } ?? "nil"
            let string = reader.stringValue(forKey: key) ?? "nil"
            print("\(key): number=\(number) string=\(string) raw=\(reader.debugValue(forKey: key))")
        }
    }

    private static func runQASample() {
        let options = QAOptions(arguments: CommandLine.arguments)
        let provider = CompositeHardwareProvider()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        for index in 0..<options.count {
            let sampleStartedAt = Date()
            let snapshot = provider.snapshotSync()
            let sampleEndedAt = Date()
            let providerDuration = durationMilliseconds(from: snapshot.readStartedAt, to: snapshot.readEndedAt)
            let record = QASampleRecord(
                sampleIndex: index,
                configuredIntervalSeconds: options.interval,
                sampleStartedAt: sampleStartedAt.iso8601Milliseconds,
                providerReadStartedAt: snapshot.readStartedAt?.iso8601Milliseconds,
                providerReadEndedAt: snapshot.readEndedAt?.iso8601Milliseconds,
                sampleEndedAt: sampleEndedAt.iso8601Milliseconds,
                providerDurationMilliseconds: providerDuration,
                sampleDurationMilliseconds: sampleEndedAt.timeIntervalSince(sampleStartedAt) * 1_000,
                stale: (providerDuration ?? 0) > options.interval * 2 * 1_000,
                raw: RawSnapshotRecord(snapshot: snapshot),
                displayed: DisplaySnapshotRecord(snapshot: snapshot, temperatureUnit: options.temperatureUnit),
                warnings: snapshot.availabilityWarnings,
                validationWarnings: MetricValidation.warnings(for: snapshot),
                bottleneckTitle: snapshot.bottleneck.title,
                bottleneckDetail: snapshot.bottleneck.detail,
                bottleneckSeverity: snapshot.bottleneck.severity.rawValue
            )

            if let data = try? encoder.encode(record), let line = String(data: data, encoding: .utf8) {
                print(line)
            }

            if index < options.count - 1 {
                Thread.sleep(forTimeInterval: options.interval)
            }
        }
    }

    private static func durationMilliseconds(from start: Date?, to end: Date?) -> Double? {
        guard let start, let end else { return nil }
        return end.timeIntervalSince(start) * 1_000
    }
}

private struct QAOptions {
    var count: Int = 1
    var interval: Double = 1
    var temperatureUnit: TemperatureUnit = .celsius

    init(arguments: [String]) {
        count = max(Self.intValue(after: "--count", in: arguments) ?? count, 1)
        interval = max(Self.doubleValue(after: "--interval", in: arguments) ?? interval, 0.1)

        if let unitRaw = Self.stringValue(after: "--temperature-unit", in: arguments),
           let unit = TemperatureUnit(rawValue: unitRaw) {
            temperatureUnit = unit
        }
    }

    private static func stringValue(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func intValue(after flag: String, in arguments: [String]) -> Int? {
        stringValue(after: flag, in: arguments).flatMap(Int.init)
    }

    private static func doubleValue(after flag: String, in arguments: [String]) -> Double? {
        stringValue(after: flag, in: arguments).flatMap(Double.init)
    }
}

private struct QASampleRecord: Codable {
    var sampleIndex: Int
    var configuredIntervalSeconds: Double
    var sampleStartedAt: String
    var providerReadStartedAt: String?
    var providerReadEndedAt: String?
    var sampleEndedAt: String
    var providerDurationMilliseconds: Double?
    var sampleDurationMilliseconds: Double
    var stale: Bool
    var raw: RawSnapshotRecord
    var displayed: DisplaySnapshotRecord
    var warnings: [String]
    var validationWarnings: [String]
    var bottleneckTitle: String
    var bottleneckDetail: String
    var bottleneckSeverity: String
}

private struct RawSnapshotRecord: Codable {
    var timestamp: String
    var fans: [FanRecord]
    var cpu: CPURecord
    var memory: MemoryRecord
    var thermals: [ThermalRecord]

    init(snapshot: HardwareSnapshot) {
        timestamp = snapshot.timestamp.iso8601Milliseconds
        fans = snapshot.fans.map(FanRecord.init)
        cpu = CPURecord(reading: snapshot.cpu)
        memory = MemoryRecord(reading: snapshot.memory)
        thermals = snapshot.thermals.map(ThermalRecord.init)
    }
}

private struct DisplaySnapshotRecord: Codable {
    var fans: [FanDisplayRecord]
    var cpuUsage: String
    var coreCount: String
    var memoryUsed: String
    var memoryAvailable: String
    var memoryPressure: String
    var compressedMemory: String
    var thermals: [ThermalDisplayRecord]

    init(snapshot: HardwareSnapshot, temperatureUnit: TemperatureUnit) {
        fans = snapshot.fans.map(FanDisplayRecord.init)
        cpuUsage = DisplayValueFormatter.percent(snapshot.cpu.usagePercent)
        coreCount = "\(snapshot.cpu.coreCount) cores"
        memoryUsed = DisplayValueFormatter.percent(snapshot.memory.usedPercent)
        memoryAvailable = snapshot.memory.availableDisplay
        memoryPressure = DisplayValueFormatter.percent(snapshot.memory.pressurePercent)
        compressedMemory = snapshot.memory.compressedDisplay
        thermals = snapshot.thermals.map { ThermalDisplayRecord(reading: $0, unit: temperatureUnit) }
    }
}

private struct FanRecord: Codable {
    var id: String
    var name: String
    var currentRPM: Double?
    var minRPM: Double?
    var maxRPM: Double?
    var normalizedLoad: Double?

    init(reading: FanReading) {
        id = reading.id
        name = reading.name
        currentRPM = reading.currentRPM
        minRPM = reading.minRPM
        maxRPM = reading.maxRPM
        normalizedLoad = reading.normalizedLoad
    }
}

private struct FanDisplayRecord: Codable {
    var id: String
    var name: String
    var rpm: String
    var percent: String
    var range: String

    init(reading: FanReading) {
        id = reading.id
        name = reading.name
        rpm = DisplayValueFormatter.rpm(reading.currentRPM)
        percent = DisplayValueFormatter.fanLoad(reading.normalizedLoad)
        range = DisplayValueFormatter.fanRange(min: reading.minRPM, max: reading.maxRPM)
    }
}

private struct CPURecord: Codable {
    var modelName: String
    var coreCount: Int
    var usagePercent: Double

    init(reading: CPUReading) {
        modelName = reading.modelName
        coreCount = reading.coreCount
        usagePercent = reading.usagePercent
    }
}

private struct MemoryRecord: Codable {
    var totalBytes: UInt64
    var usedBytes: UInt64
    var availableBytes: UInt64
    var activeBytes: UInt64
    var wiredBytes: UInt64
    var cachedBytes: UInt64
    var compressedBytes: UInt64
    var freeBytes: UInt64
    var topProcesses: [MemoryProcessRecord]
    var usedPercent: Double
    var pressurePercent: Double
    var status: String

    init(reading: MemoryReading) {
        totalBytes = reading.totalBytes
        usedBytes = reading.usedBytes
        availableBytes = reading.availableBytes
        activeBytes = reading.activeBytes
        wiredBytes = reading.wiredBytes
        cachedBytes = reading.cachedBytes
        compressedBytes = reading.compressedBytes
        freeBytes = reading.freeBytes
        topProcesses = reading.topProcesses.map(MemoryProcessRecord.init)
        usedPercent = reading.usedPercent
        pressurePercent = reading.pressurePercent
        status = reading.status.rawValue
    }
}

private struct MemoryProcessRecord: Codable {
    var pid: Int32
    var parentPid: Int32?
    var name: String
    var commandPath: String?
    var residentBytes: UInt64

    init(reading: MemoryProcessReading) {
        pid = reading.pid
        parentPid = reading.parentPid
        name = reading.name
        commandPath = reading.commandPath
        residentBytes = reading.residentBytes
    }
}

private struct ThermalRecord: Codable {
    var label: String
    var celsius: Double?
    var source: String

    init(reading: ThermalReading) {
        label = reading.label
        celsius = reading.celsius
        source = reading.source
    }
}

private struct ThermalDisplayRecord: Codable {
    var label: String
    var value: String
    var source: String

    init(reading: ThermalReading, unit: TemperatureUnit) {
        label = reading.label
        value = DisplayValueFormatter.temperature(reading.celsius, unit: unit)
        source = reading.source
    }
}

private extension Date {
    var iso8601Milliseconds: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}
