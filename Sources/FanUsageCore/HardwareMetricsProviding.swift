import Foundation

public protocol HardwareMetricsProviding: Sendable {
    func snapshot() async -> HardwareSnapshot
}

public final class CompositeHardwareProvider: HardwareMetricsProviding, @unchecked Sendable {
    private let cpuProvider: SystemCPUProvider
    private let memoryProvider: SystemMemoryProvider
    private let smcProvider: SMCSensorProvider

    public init(
        cpuProvider: SystemCPUProvider = SystemCPUProvider(),
        memoryProvider: SystemMemoryProvider = SystemMemoryProvider(),
        smcProvider: SMCSensorProvider = SMCSensorProvider()
    ) {
        self.cpuProvider = cpuProvider
        self.memoryProvider = memoryProvider
        self.smcProvider = smcProvider
    }

    public func snapshot() async -> HardwareSnapshot {
        snapshotSync()
    }

    public func snapshotSync() -> HardwareSnapshot {
        let readStartedAt = Date()
        let cpu = cpuProvider.readCPU()
        let memory = memoryProvider.readMemory()
        let smc = smcProvider.readSensors()
        let readEndedAt = Date()
        var warnings = smc.warnings

        if smc.fans.isEmpty {
            warnings.append("Fan sensors unavailable on this Mac or blocked by SMC permissions.")
        }

        if smc.thermals.isEmpty {
            warnings.append("CPU temperature unavailable without compatible SMC thermal keys.")
        }

        let bottleneck = BottleneckAnalyzer.analyze(cpu: cpu, memory: memory, fans: smc.fans, thermals: smc.thermals)
        let snapshot = HardwareSnapshot(
            timestamp: readEndedAt,
            readStartedAt: readStartedAt,
            readEndedAt: readEndedAt,
            fans: smc.fans,
            cpu: cpu,
            memory: memory,
            thermals: smc.thermals,
            bottleneck: bottleneck,
            availabilityWarnings: warnings
        )
        var validatedSnapshot = snapshot
        validatedSnapshot.availabilityWarnings += MetricValidation.warnings(for: snapshot)
        return validatedSnapshot
    }
}

public struct UnavailableSensorProvider: HardwareMetricsProviding {
    public init() {}

    public func snapshot() async -> HardwareSnapshot {
        HardwareSnapshot(
            fans: [],
            cpu: CPUReading(modelName: "Unavailable", coreCount: 0, usagePercent: 0),
            memory: MemoryReading(totalBytes: 0, usedBytes: 0, compressedBytes: 0, pressurePercent: 0, status: .normal),
            thermals: [],
            bottleneck: BottleneckReading(title: "Unavailable", detail: "Hardware metrics are unavailable", severity: .warning, progress: 0),
            availabilityWarnings: ["Hardware sensors are unavailable."]
        )
    }
}

public enum BottleneckAnalyzer {
    public static func analyze(
        cpu: CPUReading,
        memory: MemoryReading,
        fans: [FanReading],
        thermals: [ThermalReading]
    ) -> BottleneckReading {
        let hottest = thermals.compactMap(\.celsius).max() ?? 0
        let fanLoad = fans.compactMap(\.normalizedLoad).max() ?? 0

        if memory.status == .high {
            return BottleneckReading(
                title: "Memory pressure",
                detail: "\(memory.usedDisplay) used, \(memory.availableDisplay) available, \(memory.compressedDisplay) compressed",
                severity: .critical,
                progress: memory.pressurePercent / 100
            )
        }

        if hottest >= 88 {
            return BottleneckReading(
                title: "Thermal limit",
                detail: DisplayValueFormatter.thermalLimitDetail(hottestCelsius: hottest, unit: .celsius),
                severity: .critical,
                progress: hottest / 100
            )
        }

        if cpu.usagePercent >= 82 {
            return BottleneckReading(
                title: "CPU-bound",
                detail: "CPU is busy across \(cpu.coreCount) cores",
                severity: .warning,
                progress: cpu.usagePercent / 100
            )
        }

        if memory.status == .elevated {
            return BottleneckReading(
                title: "Memory getting tight",
                detail: "\(memory.usedDisplay) used, \(memory.availableDisplay) available",
                severity: .notice,
                progress: memory.pressurePercent / 100
            )
        }

        if fanLoad >= 0.72 || hottest >= 78 {
            return BottleneckReading(
                title: "Cooling active",
                detail: "Fans and thermals are elevated, but still within range",
                severity: .notice,
                progress: max(fanLoad, hottest / 100)
            )
        }

        return BottleneckReading(
            title: "No obvious bottleneck",
            detail: "CPU, memory, and thermals look healthy",
            severity: .normal,
            progress: max(cpu.usagePercent / 100, memory.pressurePercent / 100, hottest / 100)
        )
    }
}
