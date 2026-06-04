import Darwin
import Foundation

public struct CPUStatSample: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64

    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user
        self.system = system
        self.idle = idle
        self.nice = nice
    }

    var total: UInt64 { user + system + idle + nice }
}

public enum CPUUsageCalculator {
    public static func usagePercent(previous: CPUStatSample, current: CPUStatSample) -> Double {
        let totalDelta = current.total > previous.total ? current.total - previous.total : 0
        let idleDelta = current.idle > previous.idle ? current.idle - previous.idle : 0

        guard totalDelta > 0 else {
            return 0
        }

        let activeDelta = totalDelta > idleDelta ? totalDelta - idleDelta : 0
        return min(max((Double(activeDelta) / Double(totalDelta)) * 100, 0), 100)
    }
}

public final class SystemCPUProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var previousSample: CPUStatSample?

    public init() {}

    public func readCPU() -> CPUReading {
        let sample = readSample()
        let usage: Double

        lock.lock()
        if let previousSample {
            usage = CPUUsageCalculator.usagePercent(previous: previousSample, current: sample)
        } else {
            usage = 0
        }
        previousSample = sample
        lock.unlock()

        return CPUReading(
            modelName: readModelName(),
            coreCount: Int(ProcessInfo.processInfo.processorCount),
            usagePercent: usage
        )
    }

    private func readSample() -> CPUStatSample {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &load) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return CPUStatSample(user: 0, system: 0, idle: 0, nice: 0)
        }

        return CPUStatSample(
            user: UInt64(load.cpu_ticks.0),
            system: UInt64(load.cpu_ticks.1),
            idle: UInt64(load.cpu_ticks.2),
            nice: UInt64(load.cpu_ticks.3)
        )
    }

    private func readModelName() -> String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)

        if size > 0 {
            var buffer = [CChar](repeating: 0, count: size)
            let result = sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
            if result == 0 {
                let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                let value = String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    return value
                }
            }
        }

        var machine = utsname()
        uname(&machine)
        let identifier = withUnsafePointer(to: &machine.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return identifier.isEmpty ? "Apple Silicon" : identifier
    }
}
