import XCTest
@testable import FanUsageCore

final class FanUsageCoreTests: XCTestCase {
    func testCPUUsageCalculationAcrossSamples() {
        let previous = CPUStatSample(user: 100, system: 100, idle: 800, nice: 0)
        let current = CPUStatSample(user: 150, system: 150, idle: 900, nice: 0)

        XCTAssertEqual(CPUUsageCalculator.usagePercent(previous: previous, current: current), 50, accuracy: 0.001)
    }

    func testCPUUsageHandlesZeroDelta() {
        let sample = CPUStatSample(user: 100, system: 100, idle: 800, nice: 0)

        XCTAssertEqual(CPUUsageCalculator.usagePercent(previous: sample, current: sample), 0)
    }

    func testCPUUsageHandlesIdleAndFullLoad() {
        XCTAssertEqual(
            CPUUsageCalculator.usagePercent(
                previous: CPUStatSample(user: 0, system: 0, idle: 100, nice: 0),
                current: CPUStatSample(user: 0, system: 0, idle: 200, nice: 0)
            ),
            0,
            accuracy: 0.001
        )

        XCTAssertEqual(
            CPUUsageCalculator.usagePercent(
                previous: CPUStatSample(user: 100, system: 100, idle: 100, nice: 0),
                current: CPUStatSample(user: 200, system: 200, idle: 100, nice: 0)
            ),
            100,
            accuracy: 0.001
        )
    }

    func testCPUUsageHandlesCounterRollbackAsZero() {
        XCTAssertEqual(
            CPUUsageCalculator.usagePercent(
                previous: CPUStatSample(user: 300, system: 200, idle: 500, nice: 0),
                current: CPUStatSample(user: 100, system: 100, idle: 200, nice: 0)
            ),
            0,
            accuracy: 0.001
        )
    }

    func testMemoryCalculationNormalElevatedAndHigh() {
        let normal = MemoryUsageCalculator.reading(
            totalBytes: 1_000,
            pageSize: 10,
            stats: VMStats(free: 10, active: 45, inactive: 35, wired: 5, speculative: 5, compressor: 5)
        )
        XCTAssertEqual(normal.usedBytes, 550)
        XCTAssertEqual(normal.availableBytes, 500)
        XCTAssertEqual(normal.activeBytes, 450)
        XCTAssertEqual(normal.wiredBytes, 50)
        XCTAssertEqual(normal.cachedBytes, 400)
        XCTAssertEqual(normal.compressedBytes, 50)
        XCTAssertEqual(normal.freeBytes, 100)
        XCTAssertEqual(normal.pressurePercent, 55, accuracy: 0.001)
        XCTAssertEqual(normal.status, .normal)

        let elevated = MemoryUsageCalculator.reading(
            totalBytes: 1_000,
            pageSize: 10,
            stats: VMStats(free: 10, active: 65, inactive: 10, wired: 15, speculative: 0, compressor: 5)
        )
        XCTAssertEqual(elevated.pressurePercent, 85, accuracy: 0.001)
        XCTAssertEqual(elevated.status, .elevated)

        let high = MemoryUsageCalculator.reading(
            totalBytes: 1_000,
            pageSize: 10,
            stats: VMStats(free: 3, active: 70, inactive: 5, wired: 20, speculative: 0, compressor: 2)
        )
        XCTAssertEqual(high.pressurePercent, 92, accuracy: 0.001)
        XCTAssertEqual(high.status, .high)
    }

    func testMemoryCalculationTreatsInactivePagesAsAvailable() {
        let reading = MemoryUsageCalculator.reading(
            totalBytes: 1_000,
            pageSize: 10,
            stats: VMStats(free: 5, active: 30, inactive: 45, wired: 10, speculative: 5, compressor: 5)
        )

        XCTAssertEqual(reading.availableBytes, 550)
        XCTAssertEqual(reading.usedBytes, 450)
        XCTAssertEqual(reading.activeBytes, 300)
        XCTAssertEqual(reading.wiredBytes, 100)
        XCTAssertEqual(reading.cachedBytes, 500)
        XCTAssertEqual(reading.compressedBytes, 50)
        XCTAssertEqual(reading.freeBytes, 50)
        XCTAssertEqual(reading.usedPercent, 45, accuracy: 0.001)
        XCTAssertEqual(reading.pressurePercent, 45, accuracy: 0.001)
        XCTAssertEqual(reading.status, .normal)

        XCTAssertEqual(
            reading.breakdown.map(\.category),
            [.active, .wired, .compressed, .cached, .free]
        )
    }

    func testSMCParsesFanFixture() {
        let reader = FixtureSMCReader(
            values: [
                "FNum": 1,
                "F0Ac": 2400,
                "F0Mn": 1200,
                "F0Mx": 5200,
                "TC0P": 52
            ],
            strings: [
                "F0ID": "CPU fan"
            ]
        )

        let snapshot = SMCSensorProvider(reader: reader).readSensors()

        XCTAssertEqual(snapshot.fans.count, 1)
        XCTAssertEqual(snapshot.fans[0].name, "CPU fan")
        XCTAssertEqual(snapshot.fans[0].currentRPM, 2400)
        XCTAssertTrue(snapshot.fans[0].hasLiveRPM)
        XCTAssertEqual(snapshot.fans[0].normalizedLoad ?? 0, 0.3, accuracy: 0.001)
        XCTAssertEqual(snapshot.thermals.first?.celsius, 52)
    }

    func testSMCUnavailableFixtureReturnsEmptySensors() {
        let snapshot = SMCSensorProvider(reader: FixtureSMCReader(values: [:])).readSensors()

        XCTAssertTrue(snapshot.fans.isEmpty)
        XCTAssertTrue(snapshot.thermals.isEmpty)
    }

    func testSMCRejectsImplausibleThermalDrop() {
        let reader = MutableFixtureSMCReader(values: [
            "FNum": 0,
            "Tp09": 84,
            "Te05": 83
        ])
        let provider = SMCSensorProvider(reader: reader)

        let first = provider.readSensors()
        reader.values["Tp09"] = 2.2
        reader.values["Te05"] = 83
        let second = provider.readSensors()

        XCTAssertEqual(first.thermals.first { $0.label == "SoC" }?.celsius, 84)
        XCTAssertEqual(second.thermals.first { $0.label == "SoC" }?.celsius, 84)
    }

    func testSMCRejectsImpossibleThermalHighAndRecovers() {
        let reader = MutableFixtureSMCReader(values: [
            "FNum": 0,
            "Te05": 72
        ])
        let provider = SMCSensorProvider(reader: reader)

        XCTAssertEqual(provider.readSensors().thermals.first { $0.label == "Die" }?.celsius, 72)

        reader.values["Te05"] = 140
        XCTAssertEqual(provider.readSensors().thermals.first { $0.label == "Die" }?.celsius, 72)

        reader.values["Te05"] = 76
        XCTAssertEqual(provider.readSensors().thermals.first { $0.label == "Die" }?.celsius, 76)
    }

    func testSMCPreservesStableValuesPerThermalKey() {
        let reader = MutableFixtureSMCReader(values: [
            "FNum": 0,
            "Tp09": 55,
            "Te05": 75
        ])
        let provider = SMCSensorProvider(reader: reader)

        _ = provider.readSensors()
        reader.values["Tp09"] = 4
        reader.values["Te05"] = 77

        let thermals = provider.readSensors().thermals
        XCTAssertEqual(thermals.first { $0.label == "SoC" }?.celsius, 55)
        XCTAssertEqual(thermals.first { $0.label == "Die" }?.celsius, 77)
    }

    func testSMCNumericDecoding() {
        XCTAssertEqual(
            decodeNumeric(data: SMCVal(key: "F0Ac", dataSize: 4, dataType: "flt ", bytes: [0x00, 0xd0, 0x10, 0x45])) ?? -1,
            2317,
            accuracy: 0.001
        )

        XCTAssertEqual(
            decodeNumeric(data: SMCVal(key: "F0Ac", dataSize: 2, dataType: "fpe2", bytes: [0x25, 0x80])) ?? -1,
            2400,
            accuracy: 0.001
        )

        XCTAssertEqual(
            decodeNumeric(data: SMCVal(key: "TC0P", dataSize: 2, dataType: "sp78", bytes: [0x34, 0x00])) ?? -1,
            52,
            accuracy: 0.001
        )

        XCTAssertEqual(
            decodeNumeric(data: SMCVal(key: "FNum", dataSize: 1, dataType: "ui8 ", bytes: [0x02])) ?? -1,
            2,
            accuracy: 0.001
        )

        XCTAssertEqual(
            decodeNumeric(data: SMCVal(key: "LIMT", dataSize: 2, dataType: "ui16", bytes: [0x01, 0x2c])) ?? -1,
            300,
            accuracy: 0.001
        )

        XCTAssertEqual(
            decodeNumeric(data: SMCVal(key: "LONG", dataSize: 4, dataType: "ui32", bytes: [0x00, 0x00, 0x03, 0xe8])) ?? -1,
            1000,
            accuracy: 0.001
        )
    }

    func testSMCNumericDecodingRejectsBadSizesAndUnknownTypes() {
        XCTAssertNil(decodeNumeric(data: SMCVal(key: "F0Ac", dataSize: 1, dataType: "fpe2", bytes: [0x25])))
        XCTAssertNil(decodeNumeric(data: SMCVal(key: "F0Ac", dataSize: 4, dataType: "nope", bytes: [0, 0, 0, 0])))
    }

    func testDisplayValueFormatterUsesDocumentedRoundingAndUnavailableText() {
        XCTAssertEqual(DisplayValueFormatter.percent(12.5), "13%")
        XCTAssertEqual(DisplayValueFormatter.rpm(2400.4), "2400 RPM")
        XCTAssertEqual(DisplayValueFormatter.rpm(nil), "Unavailable")
        XCTAssertEqual(DisplayValueFormatter.temperature(40.4, unit: .celsius), "40 deg C")
        XCTAssertEqual(DisplayValueFormatter.temperature(nil, unit: .fahrenheit), "Unavailable")
        XCTAssertEqual(DisplayValueFormatter.fanRange(min: 1200.2, max: 5199.8), "Range 1200-5200 RPM")
        XCTAssertEqual(DisplayValueFormatter.fanRange(min: nil, max: 5200), "Range unavailable")
        XCTAssertEqual(DisplayValueFormatter.fanLoad(0.305), "31% of range")
        XCTAssertEqual(DisplayValueFormatter.fanLoad(nil), "Load unavailable")
        XCTAssertEqual(DisplayValueFormatter.thermalLimitDetail(hottestCelsius: 91, unit: .celsius), "Hottest sensor is 91 deg C; macOS may reduce performance")
        XCTAssertEqual(DisplayValueFormatter.thermalLimitDetail(hottestCelsius: 91, unit: .fahrenheit), "Hottest sensor is 196 deg F; macOS may reduce performance")
    }

    func testPlaceholderUsesLoadingStateInsteadOfWarning() {
        XCTAssertEqual(HardwareSnapshot.placeholder.cpu.modelName, "Loading")
        XCTAssertTrue(HardwareSnapshot.placeholder.availabilityWarnings.isEmpty)
    }

    func testMetricValidationFlagsImpossibleValues() {
        let snapshot = HardwareSnapshot(
            fans: [FanReading(id: "fan-0", name: "Fan 1", currentRPM: -1, minRPM: 5000, maxRPM: 1200)],
            cpu: CPUReading(modelName: "Apple M4 Pro", coreCount: 14, usagePercent: 50),
            memory: MemoryReading(totalBytes: 100, usedBytes: 40, compressedBytes: 0, pressurePercent: 40, status: .normal),
            thermals: [ThermalReading(label: "Die", celsius: 140, source: "fixture")],
            bottleneck: BottleneckReading(title: "Fixture", detail: "Fixture", severity: .normal, progress: 0)
        )

        let warnings = MetricValidation.warnings(for: snapshot)
        XCTAssertTrue(warnings.contains("Fan 1 reported an invalid RPM."))
        XCTAssertTrue(warnings.contains("Fan 1 reported an invalid RPM range."))
        XCTAssertTrue(warnings.contains("Die temperature is outside the expected range."))
    }

    func testBottleneckPrefersMemoryPressure() {
        let reading = BottleneckAnalyzer.analyze(
            cpu: CPUReading(modelName: "Apple M4 Pro", coreCount: 14, usagePercent: 20),
            memory: MemoryReading(totalBytes: 100, usedBytes: 92, compressedBytes: 25, pressurePercent: 94, status: .high),
            fans: [],
            thermals: []
        )

        XCTAssertEqual(reading.title, "Memory pressure")
        XCTAssertEqual(reading.severity, .critical)
    }

    func testBottleneckDetectsThermalLimit() {
        let reading = BottleneckAnalyzer.analyze(
            cpu: CPUReading(modelName: "Apple M4 Pro", coreCount: 14, usagePercent: 40),
            memory: MemoryReading(totalBytes: 100, usedBytes: 40, compressedBytes: 0, pressurePercent: 40, status: .normal),
            fans: [],
            thermals: [ThermalReading(label: "Die", celsius: 91, source: "SMC Te05")]
        )

        XCTAssertEqual(reading.title, "Thermal limit")
        XCTAssertEqual(reading.severity, .critical)
    }
}

private final class MutableFixtureSMCReader: SMCReading, @unchecked Sendable {
    var values: [String: Double]

    init(values: [String: Double]) {
        self.values = values
    }

    func numericValue(forKey key: String) -> Double? {
        values[key]
    }

    func stringValue(forKey key: String) -> String? {
        nil
    }
}
