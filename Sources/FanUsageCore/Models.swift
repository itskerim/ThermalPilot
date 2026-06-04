import Foundation

public struct HardwareSnapshot: Equatable, Sendable {
    public var timestamp: Date
    public var readStartedAt: Date?
    public var readEndedAt: Date?
    public var fans: [FanReading]
    public var cpu: CPUReading
    public var memory: MemoryReading
    public var thermals: [ThermalReading]
    public var bottleneck: BottleneckReading
    public var availabilityWarnings: [String]

    public init(
        timestamp: Date = Date(),
        readStartedAt: Date? = nil,
        readEndedAt: Date? = nil,
        fans: [FanReading],
        cpu: CPUReading,
        memory: MemoryReading,
        thermals: [ThermalReading],
        bottleneck: BottleneckReading,
        availabilityWarnings: [String] = []
    ) {
        self.timestamp = timestamp
        self.readStartedAt = readStartedAt
        self.readEndedAt = readEndedAt
        self.fans = fans
        self.cpu = cpu
        self.memory = memory
        self.thermals = thermals
        self.bottleneck = bottleneck
        self.availabilityWarnings = availabilityWarnings
    }

    public static let placeholder = HardwareSnapshot(
        fans: [],
        cpu: CPUReading(modelName: "Loading", coreCount: 0, usagePercent: 0),
        memory: MemoryReading(totalBytes: 0, usedBytes: 0, compressedBytes: 0, pressurePercent: 0, status: .normal),
        thermals: [],
        bottleneck: BottleneckReading(title: "Sampling", detail: "Waiting for live metrics", severity: .normal, progress: 0),
        availabilityWarnings: []
    )
}

public struct FanReading: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var currentRPM: Double?
    public var minRPM: Double?
    public var maxRPM: Double?

    public init(id: String, name: String, currentRPM: Double?, minRPM: Double?, maxRPM: Double?) {
        self.id = id
        self.name = name
        self.currentRPM = currentRPM
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }

    public var normalizedLoad: Double? {
        guard let currentRPM, let minRPM, let maxRPM, maxRPM > minRPM else {
            return nil
        }
        return min(max((currentRPM - minRPM) / (maxRPM - minRPM), 0), 1)
    }

    public var hasLiveRPM: Bool {
        guard let currentRPM else {
            return false
        }
        return currentRPM.isFinite && currentRPM > 0
    }
}

public struct CPUReading: Equatable, Sendable {
    public var modelName: String
    public var coreCount: Int
    public var usagePercent: Double

    public init(modelName: String, coreCount: Int, usagePercent: Double) {
        self.modelName = modelName
        self.coreCount = coreCount
        self.usagePercent = min(max(usagePercent, 0), 100)
    }
}

public struct MemoryReading: Equatable, Sendable {
    public var totalBytes: UInt64
    public var usedBytes: UInt64
    public var availableBytes: UInt64
    public var activeBytes: UInt64
    public var wiredBytes: UInt64
    public var cachedBytes: UInt64
    public var compressedBytes: UInt64
    public var freeBytes: UInt64
    public var topProcesses: [MemoryProcessReading]
    public var pressurePercent: Double
    public var status: MemoryStatus

    public init(
        totalBytes: UInt64,
        usedBytes: UInt64,
        availableBytes: UInt64? = nil,
        activeBytes: UInt64? = nil,
        wiredBytes: UInt64? = nil,
        cachedBytes: UInt64 = 0,
        compressedBytes: UInt64,
        freeBytes: UInt64 = 0,
        topProcesses: [MemoryProcessReading] = [],
        pressurePercent: Double,
        status: MemoryStatus
    ) {
        self.totalBytes = totalBytes
        self.usedBytes = min(usedBytes, totalBytes)
        self.availableBytes = min(availableBytes ?? totalBytes.saturatingSubtract(usedBytes), totalBytes)
        self.activeBytes = min(activeBytes ?? usedBytes.saturatingSubtract(compressedBytes), totalBytes)
        self.wiredBytes = min(wiredBytes ?? 0, totalBytes)
        self.cachedBytes = min(cachedBytes, totalBytes)
        self.compressedBytes = compressedBytes
        self.freeBytes = min(freeBytes, totalBytes)
        self.topProcesses = topProcesses
        self.pressurePercent = min(max(pressurePercent, 0), 100)
        self.status = status
    }

    public var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(usedBytes) / Double(totalBytes) * 100, 0), 100)
    }

    public var usedDisplay: String {
        ByteCountFormatter.fanUsageMemoryFormatter.string(fromByteCount: Int64(usedBytes))
    }

    public var availableDisplay: String {
        ByteCountFormatter.fanUsageMemoryFormatter.string(fromByteCount: Int64(availableBytes))
    }

    public var totalDisplay: String {
        ByteCountFormatter.fanUsageMemoryFormatter.string(fromByteCount: Int64(totalBytes))
    }

    public var compressedDisplay: String {
        ByteCountFormatter.fanUsageMemoryFormatter.string(fromByteCount: Int64(compressedBytes))
    }

    public var freeDisplay: String {
        ByteCountFormatter.fanUsageMemoryFormatter.string(fromByteCount: Int64(freeBytes))
    }

    public var cachedDisplay: String {
        ByteCountFormatter.fanUsageMemoryFormatter.string(fromByteCount: Int64(cachedBytes))
    }

    public var breakdown: [MemoryBreakdownItem] {
        [
            MemoryBreakdownItem(category: .active, bytes: activeBytes),
            MemoryBreakdownItem(category: .wired, bytes: wiredBytes),
            MemoryBreakdownItem(category: .compressed, bytes: compressedBytes),
            MemoryBreakdownItem(category: .cached, bytes: cachedBytes),
            MemoryBreakdownItem(category: .free, bytes: freeBytes)
        ]
    }
}

public struct MemoryProcessReading: Identifiable, Equatable, Sendable {
    public var pid: Int32
    public var parentPid: Int32?
    public var name: String
    public var commandPath: String?
    public var residentBytes: UInt64

    public init(pid: Int32, parentPid: Int32? = nil, name: String, commandPath: String?, residentBytes: UInt64) {
        self.pid = pid
        self.parentPid = parentPid
        self.name = name
        self.commandPath = commandPath
        self.residentBytes = residentBytes
    }

    public var id: String {
        "\(pid)-\(name)"
    }

    public var display: String {
        ByteCountFormatter.fanUsageMemoryFormatter.string(fromByteCount: Int64(residentBytes))
    }
}

public struct MemoryBreakdownItem: Identifiable, Equatable, Sendable {
    public var category: MemoryCategory
    public var bytes: UInt64

    public init(category: MemoryCategory, bytes: UInt64) {
        self.category = category
        self.bytes = bytes
    }

    public var id: MemoryCategory { category }

    public var display: String {
        ByteCountFormatter.fanUsageMemoryFormatter.string(fromByteCount: Int64(bytes))
    }
}

public enum MemoryCategory: String, CaseIterable, Equatable, Sendable {
    case active
    case wired
    case compressed
    case cached
    case free

    public var label: String {
        switch self {
        case .active: "Active"
        case .wired: "Wired"
        case .compressed: "Compressed"
        case .cached: "Cached"
        case .free: "Free"
        }
    }

    public var explanation: String {
        switch self {
        case .active:
            "Memory currently used by running apps and processes."
        case .wired:
            "System memory that macOS must keep resident and cannot compress or page out."
        case .compressed:
            "Memory macOS compressed to avoid writing data to disk."
        case .cached:
            "Recently used file and app data that macOS can reclaim when apps need RAM."
        case .free:
            "Unused memory immediately available to apps."
        }
    }
}

public enum MemoryStatus: String, Equatable, Sendable {
    case normal
    case elevated
    case high

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .elevated: "Elevated"
        case .high: "High"
        }
    }
}

public struct BottleneckReading: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var severity: BottleneckSeverity
    public var progress: Double

    public init(title: String, detail: String, severity: BottleneckSeverity, progress: Double) {
        self.title = title
        self.detail = detail
        self.severity = severity
        self.progress = min(max(progress, 0), 1)
    }
}

public enum BottleneckSeverity: String, Equatable, Sendable {
    case normal
    case notice
    case warning
    case critical
}

public struct ThermalReading: Identifiable, Equatable, Sendable {
    public var id: String { label }
    public var label: String
    public var celsius: Double?
    public var source: String

    public init(label: String, celsius: Double?, source: String) {
        self.label = label
        self.celsius = celsius
        self.source = source
    }
}

private extension ByteCountFormatter {
    static var fanUsageMemoryFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }
}

public enum TemperatureUnit: String, CaseIterable, Identifiable, Sendable {
    case celsius
    case fahrenheit

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .celsius: "C"
        case .fahrenheit: "F"
        }
    }

    public func displayValue(for celsius: Double) -> String {
        switch self {
        case .celsius:
            "\(Int(celsius.rounded())) deg C"
        case .fahrenheit:
            "\(Int(((celsius * 9 / 5) + 32).rounded())) deg F"
        }
    }
}

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case cpu
    case fan
    case temperature
    case iconOnly

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .cpu: "CPU %"
        case .fan: "Fan RPM"
        case .temperature: "Temperature"
        case .iconOnly: "Icon only"
        }
    }
}

public enum DisplayValueFormatter {
    public static func percent(_ value: Double) -> String {
        guard value.isFinite else { return "Unavailable" }
        return "\(Int(value.rounded()))%"
    }

    public static func rpm(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        return "\(Int(value.rounded())) RPM"
    }

    public static func compactRPM(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Fan" }
        return "\(Int(value.rounded()))"
    }

    public static func temperature(_ value: Double?, unit: TemperatureUnit) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        return unit.displayValue(for: value)
    }

    public static func fanRange(min: Double?, max: Double?) -> String {
        guard let min, let max, min.isFinite, max.isFinite else {
            return "Range unavailable"
        }
        return "Range \(Int(min.rounded()))-\(Int(max.rounded())) RPM"
    }

    public static func fanLoad(_ normalizedLoad: Double?) -> String {
        guard let normalizedLoad, normalizedLoad.isFinite else {
            return "Load unavailable"
        }
        return "\(percent(normalizedLoad * 100)) of range"
    }

    public static func thermalLimitDetail(hottestCelsius: Double, unit: TemperatureUnit) -> String {
        let temperature = temperature(hottestCelsius, unit: unit)
        return "Hottest sensor is \(temperature); macOS may reduce performance"
    }
}

public enum MetricValidation {
    public static func warnings(for snapshot: HardwareSnapshot) -> [String] {
        var warnings: [String] = []

        for fan in snapshot.fans {
            if let rpm = fan.currentRPM, (!rpm.isFinite || rpm < 0) {
                warnings.append("\(fan.name) reported an invalid RPM.")
            }
            if let min = fan.minRPM, let max = fan.maxRPM, max <= min {
                warnings.append("\(fan.name) reported an invalid RPM range.")
            }
        }

        if snapshot.cpu.usagePercent < 0 || snapshot.cpu.usagePercent > 100 || !snapshot.cpu.usagePercent.isFinite {
            warnings.append("CPU usage is outside the expected 0-100% range.")
        }

        if snapshot.memory.usedBytes > snapshot.memory.totalBytes {
            warnings.append("Memory used exceeds physical memory.")
        }

        for thermal in snapshot.thermals {
            if let celsius = thermal.celsius, (!celsius.isFinite || celsius < 0 || celsius > 115) {
                warnings.append("\(thermal.label) temperature is outside the expected range.")
            }
        }

        return warnings
    }
}

private extension UInt64 {
    func saturatingSubtract(_ other: UInt64) -> UInt64 {
        self > other ? self - other : 0
    }
}
