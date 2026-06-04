import Darwin
import Foundation

public final class SystemMemoryProvider: @unchecked Sendable {
    public init() {}

    public func readMemory() -> MemoryReading {
        let total = ProcessInfo.processInfo.physicalMemory
        let stats = readVMStats()
        let pageSize = readPageSize()
        let topProcesses = readTopProcesses(limit: 40)

        return MemoryUsageCalculator.reading(totalBytes: total, pageSize: pageSize, stats: stats, topProcesses: topProcesses)
    }

    private func readVMStats() -> VMStats {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return VMStats()
        }

        return VMStats(
            free: UInt64(stats.free_count),
            active: UInt64(stats.active_count),
            inactive: UInt64(stats.inactive_count),
            wired: UInt64(stats.wire_count),
            speculative: UInt64(stats.speculative_count),
            compressor: UInt64(stats.compressor_page_count)
        )
    }

    private func readPageSize() -> UInt64 {
        var size = vm_size_t(0)
        host_page_size(mach_host_self(), &size)
        return UInt64(size)
    }

    private func readTopProcesses(limit: Int) -> [MemoryProcessReading] {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,rss=,comm="]
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            return []
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n")
            .compactMap(Self.parseProcessLine)
            .sorted { $0.residentBytes > $1.residentBytes }
            .prefix(limit)
            .map { $0 }
    }

    private static func parseProcessLine(_ line: Substring) -> MemoryProcessReading? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }

        let parts = trimmed.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard parts.count == 4,
              let pid = Int32(parts[0]),
              let parentPid = Int32(parts[1]),
              let rssKilobytes = UInt64(parts[2]) else {
            return nil
        }

        let command = String(parts[3])
        let name = URL(fileURLWithPath: command).lastPathComponent
        return MemoryProcessReading(
            pid: pid,
            parentPid: parentPid,
            name: name.isEmpty ? command : name,
            commandPath: command.hasPrefix("/") ? command : nil,
            residentBytes: rssKilobytes.saturatingMultiply(1_024)
        )
    }
}

public struct VMStats: Equatable, Sendable {
    public var free: UInt64
    public var active: UInt64
    public var inactive: UInt64
    public var wired: UInt64
    public var speculative: UInt64
    public var compressor: UInt64

    public init(
        free: UInt64 = 0,
        active: UInt64 = 0,
        inactive: UInt64 = 0,
        wired: UInt64 = 0,
        speculative: UInt64 = 0,
        compressor: UInt64 = 0
    ) {
        self.free = free
        self.active = active
        self.inactive = inactive
        self.wired = wired
        self.speculative = speculative
        self.compressor = compressor
    }
}

public enum MemoryUsageCalculator {
    public static func reading(
        totalBytes: UInt64,
        pageSize: UInt64,
        stats: VMStats,
        topProcesses: [MemoryProcessReading] = []
    ) -> MemoryReading {
        let availablePages = stats.free
            .saturatingAdd(stats.inactive)
            .saturatingAdd(stats.speculative)
        let availableBytes = min(availablePages.saturatingMultiply(pageSize), totalBytes)
        let freeBytes = min(stats.free.saturatingMultiply(pageSize), totalBytes)
        let cachedPages = stats.inactive.saturatingAdd(stats.speculative)
        let cachedBytes = min(cachedPages.saturatingMultiply(pageSize), totalBytes)
        let activeBytes = min(stats.active.saturatingMultiply(pageSize), totalBytes)
        let wiredBytes = min(stats.wired.saturatingMultiply(pageSize), totalBytes)
        let usedPages = stats.active
            .saturatingAdd(stats.wired)
            .saturatingAdd(stats.compressor)
        let calculatedUsedBytes = usedPages.saturatingMultiply(pageSize)
        let compressedBytes = stats.compressor.saturatingMultiply(pageSize)
        let usedBytes = min(calculatedUsedBytes, totalBytes)
        let pressure = totalBytes > 0 ? Double(min(usedBytes, totalBytes)) / Double(totalBytes) * 100 : 0

        let status: MemoryStatus
        if pressure >= 88 || compressedBytes > totalBytes / 5 {
            status = .high
        } else if pressure >= 74 || compressedBytes > totalBytes / 10 {
            status = .elevated
        } else {
            status = .normal
        }

        return MemoryReading(
            totalBytes: totalBytes,
            usedBytes: usedBytes,
            availableBytes: availableBytes,
            activeBytes: activeBytes,
            wiredBytes: wiredBytes,
            cachedBytes: cachedBytes,
            compressedBytes: compressedBytes,
            freeBytes: freeBytes,
            topProcesses: topProcesses,
            pressurePercent: pressure,
            status: status
        )
    }
}

private extension UInt64 {
    func saturatingAdd(_ other: UInt64) -> UInt64 {
        let result = addingReportingOverflow(other)
        return result.overflow ? UInt64.max : result.partialValue
    }

    func saturatingMultiply(_ other: UInt64) -> UInt64 {
        let result = multipliedReportingOverflow(by: other)
        return result.overflow ? UInt64.max : result.partialValue
    }
}
