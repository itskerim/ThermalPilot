import FanUsageCore
import ServiceManagement
import AppKit
import SwiftUI

private struct TemperatureUnitKey: EnvironmentKey {
    static let defaultValue: TemperatureUnit = .celsius
}

extension EnvironmentValues {
    var temperatureUnit: TemperatureUnit {
        get { self[TemperatureUnitKey.self] }
        set { self[TemperatureUnitKey.self] = newValue }
    }
}

struct ContentView: View {
    @ObservedObject var model: MetricsModel
    @AppStorage("refreshInterval") private var refreshInterval = 3.0
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayModeRaw = MenuBarDisplayMode.cpu.rawValue
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @Environment(\.temperatureUnit) private var temperatureUnit
    @State private var selectedTab: SidebarTab = .overview
    @State private var launchAtLoginError: String?
    @State private var isRevertingLaunchAtLogin = false

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                Sidebar(selectedTab: $selectedTab) { tab in
                    withAnimation(.snappy(duration: 0.26)) {
                        selectedTab = tab
                        proxy.scrollTo(tab.anchorID, anchor: .top)
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        Header(snapshot: model.snapshot)
                            .id(SidebarTab.overview.anchorID)
                            .sectionMarker(.overview)
                        FansSection(snapshot: model.snapshot)
                            .id(SidebarTab.fans.anchorID)
                            .sectionMarker(.fans)
                        CPUSection(snapshot: model.snapshot)
                            .id(SidebarTab.cpu.anchorID)
                            .sectionMarker(.cpu)
                        MemorySection(snapshot: model.snapshot)
                            .id(SidebarTab.memory.anchorID)
                            .sectionMarker(.memory)
                        ThermalsSection(snapshot: model.snapshot, unit: temperatureUnit)
                            .id(SidebarTab.thermals.anchorID)
                            .sectionMarker(.thermals)
                        BottleneckSection(snapshot: model.snapshot, unit: temperatureUnit)
                        WarningsSection(warnings: model.snapshot.availabilityWarnings, isSampling: model.lastPublishedAt == nil)
                        SettingsSection(
                            refreshInterval: $refreshInterval,
                            temperatureUnitRaw: $temperatureUnitRaw,
                            menuBarDisplayModeRaw: $menuBarDisplayModeRaw,
                            launchAtLogin: $launchAtLogin,
                            launchAtLoginError: launchAtLoginError
                        )
                        .id(SidebarTab.settings.anchorID)
                        .sectionMarker(.settings)
                        Footer(
                            nextRefreshSeconds: model.nextRefreshSeconds,
                            lastPublishedAt: model.lastPublishedAt,
                            isStale: model.isLastRefreshStale
                        ) {
                            model.refreshNow()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                }
                .coordinateSpace(name: "contentScroll")
                .onPreferenceChange(SectionOffsetPreferenceKey.self) { offsets in
                    updateSelectedTab(from: offsets)
                }
                .background(Color.panelBackground)
            }
            .background(Color.panelBackground)
        }
        .preferredColorScheme(.dark)
        .onChange(of: launchAtLogin) { _, enabled in
            if isRevertingLaunchAtLogin {
                isRevertingLaunchAtLogin = false
                return
            }
            setLaunchAtLogin(enabled)
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Launch at login could not be changed in System Settings."
            isRevertingLaunchAtLogin = true
            launchAtLogin.toggle()
        }
    }

    private func updateSelectedTab(from offsets: [SidebarTab: CGFloat]) {
        let visibleTabs = SidebarTab.contentTabs
            .compactMap { tab -> (SidebarTab, CGFloat)? in
                guard let offset = offsets[tab] else { return nil }
                return (tab, offset)
            }

        guard let nearest = visibleTabs
            .filter({ $0.1 <= 42 })
            .max(by: { $0.1 < $1.1 }) ?? visibleTabs.min(by: { abs($0.1) < abs($1.1) }) else {
            return
        }

        if selectedTab != nearest.0 {
            selectedTab = nearest.0
        }
    }
}

private enum SidebarTab: String, CaseIterable, Identifiable {
    case overview
    case fans
    case cpu
    case memory
    case thermals
    case settings

    var id: String { rawValue }
    static let contentTabs: [SidebarTab] = [.overview, .fans, .cpu, .memory, .thermals, .settings]
    var anchorID: String { "section-\(rawValue)" }

    var systemName: String {
        switch self {
        case .overview: "gauge.with.dots.needle.67percent"
        case .fans: "fan"
        case .cpu: "memorychip"
        case .memory: "chart.pie"
        case .thermals: "thermometer.medium"
        case .settings: "gearshape"
        }
    }

    var color: Color {
        switch self {
        case .overview: .accentPlatinum
        case .fans: .accentSage
        case .cpu: .accentIndigo
        case .memory: .accentPlatinum
        case .thermals: .accentCopper
        case .settings: .secondaryText
        }
    }
}

private struct Sidebar: View {
    @Binding var selectedTab: SidebarTab
    var select: (SidebarTab) -> Void

    var body: some View {
        VStack(spacing: 20) {
            ForEach([SidebarTab.overview, .fans, .cpu, .memory, .thermals]) { tab in
                Button {
                    select(tab)
                } label: {
                    SidebarIcon(
                        systemName: tab.systemName,
                        color: tab.color,
                        selected: selectedTab == tab
                    )
                }
                .buttonStyle(.plain)
                .help(tab.rawValue.capitalized)
            }
            Spacer()
            Button {
                select(.settings)
            } label: {
                SidebarIcon(
                    systemName: SidebarTab.settings.systemName,
                    color: SidebarTab.settings.color,
                    selected: selectedTab == .settings
                )
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
        .frame(width: 48)
        .padding(.vertical, 18)
        .background(Color.sidebarBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Color.white.opacity(0.075))
                .frame(width: 1)
        }
    }
}

private struct SidebarIcon: View {
    var systemName: String
    var color: Color
    var selected = false
    @State private var isHovering = false

    var body: some View {
        ZStack(alignment: .leading) {
            if selected {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentPlatinum)
                    .frame(width: 3, height: 34)
                    .offset(x: -11)
            }
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selected ? color : Color.secondaryText.opacity(0.72))
                .frame(width: 30, height: 30)
                .scaleEffect(isHovering ? 1.08 : 1.0)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.smooth(duration: 0.16)) {
                isHovering = hovering
            }
        }
    }
}

private struct SectionOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: [SidebarTab: CGFloat] = [:]

    static func reduce(value: inout [SidebarTab: CGFloat], nextValue: () -> [SidebarTab: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

private struct SectionMarker: ViewModifier {
    var tab: SidebarTab

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SectionOffsetPreferenceKey.self,
                    value: [tab: proxy.frame(in: .named("contentScroll")).minY]
                )
            }
        }
    }
}

private extension View {
    func sectionMarker(_ tab: SidebarTab) -> some View {
        modifier(SectionMarker(tab: tab))
    }
}

private struct Header: View {
    var snapshot: HardwareSnapshot

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Thermal Pilot")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color.primaryText)
                Text(snapshot.cpu.modelName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

private struct StatusSummary: View {
    var snapshot: HardwareSnapshot
    var unit: TemperatureUnit

    var body: some View {
        HStack(spacing: 8) {
            SummaryChip(title: "CPU", value: DisplayValueFormatter.percent(snapshot.cpu.usagePercent), tint: .accentIndigo)
            SummaryChip(title: "Memory", value: snapshot.memory.status.label, tint: memoryTint)
            SummaryChip(title: "Hottest", value: hottestDisplay, tint: thermalTint)
            SummaryChip(title: "Slowdown", value: snapshot.bottleneck.title, tint: slowdownTint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status summary. CPU \(DisplayValueFormatter.percent(snapshot.cpu.usagePercent)), memory \(snapshot.memory.status.label), hottest \(hottestDisplay), slowdown \(snapshot.bottleneck.title).")
    }

    private var hottestDisplay: String {
        DisplayValueFormatter.temperature(snapshot.thermals.compactMap(\.celsius).max(), unit: unit)
    }

    private var memoryTint: Color {
        switch snapshot.memory.status {
        case .normal: .accentIndigo
        case .elevated: .accentPlatinum
        case .high: .accentCopper
        }
    }

    private var thermalTint: Color {
        let hottest = snapshot.thermals.compactMap(\.celsius).max() ?? 0
        return hottest > 78 ? .accentCopper : .accentSage
    }

    private var slowdownTint: Color {
        switch snapshot.bottleneck.severity {
        case .normal: .accentSage
        case .notice: .accentPlatinum
        case .warning, .critical: .accentCopper
        }
    }
}

private struct SummaryChip: View {
    var title: String
    var value: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.secondaryText)
            Text(value)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.075))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(tint.opacity(0.20), lineWidth: 1)
                )
        )
    }
}

private struct FansSection: View {
    var snapshot: HardwareSnapshot

    var body: some View {
        MetricGroup(
            title: "Fans",
            pill: fansPill,
            systemImage: "fan",
            tint: .accentSage
        ) {
            if snapshot.fans.isEmpty {
                EmptyMetricLine(
                    title: "Cooling fans",
                    value: fansEmptyValue,
                    detail: fansEmptyDetail,
                    accessibilityPrefix: "fans.empty"
                )
            } else {
                ForEach(snapshot.fans) { fan in
                    MetricLine(
                        title: fan.name,
                        progress: fanProgress(for: fan),
                        value: DisplayValueFormatter.rpm(fan.currentRPM),
                        progressLabel: fanProgressLabel(for: fan),
                        detail: DisplayValueFormatter.fanRange(min: fan.minRPM, max: fan.maxRPM),
                        tint: .accentSage,
                        helpText: "RPM is the live fan speed. The bar shows how far that speed sits between the reported minimum and maximum fan range.",
                        accessibilityPrefix: "fan.\(fan.id)"
                    )
                }
            }
        }
    }

    private var fansPill: String {
        if snapshot.cpu.modelName == "Loading" {
            return "Sampling"
        }
        return snapshot.fans.isEmpty ? "Unsupported" : "\(snapshot.fans.count) active"
    }

    private var fansEmptyValue: String {
        snapshot.cpu.modelName == "Loading" ? "Sampling" : "Unsupported"
    }

    private var fansEmptyDetail: String {
        if snapshot.cpu.modelName == "Loading" {
            return "Fan readings will appear after the first sample."
        }
        if snapshot.availabilityWarnings.contains(where: { $0.localizedCaseInsensitiveContains("blocked") }) {
            return "macOS did not expose fan sensors, or SMC access is blocked on this Mac."
        }
        return "This Mac does not expose fan RPM through compatible SMC keys."
    }

    private func fanProgress(for fan: FanReading) -> Double {
        if let normalizedLoad = fan.normalizedLoad {
            return max(normalizedLoad, fan.hasLiveRPM ? 0.03 : 0)
        }
        return fan.hasLiveRPM ? 0.03 : 0
    }

    private func fanProgressLabel(for fan: FanReading) -> String {
        if fan.hasLiveRPM, let normalizedLoad = fan.normalizedLoad {
            return DisplayValueFormatter.fanLoad(normalizedLoad)
        }
        if fan.hasLiveRPM {
            return "Live RPM"
        }
        return "No RPM"
    }
}

private struct CPUSection: View {
    var snapshot: HardwareSnapshot

    var body: some View {
        MetricGroup(title: "CPU", pill: "\(snapshot.cpu.coreCount) cores", systemImage: "cpu", tint: .accentIndigo) {
            MetricLine(
                title: "Total usage",
                progress: snapshot.cpu.usagePercent / 100,
                value: DisplayValueFormatter.percent(snapshot.cpu.usagePercent),
                detail: "Public host CPU stats",
                tint: .accentIndigo,
                accessibilityPrefix: "cpu.total"
            )
        }
    }
}

private struct MemorySection: View {
    var snapshot: HardwareSnapshot
    @State private var isBreakdownExpanded = false

    var body: some View {
        MetricGroup(title: "Memory", pill: snapshot.memory.status.label, systemImage: "memorychip", tint: memoryTint) {
            MetricLine(
                title: "Memory use",
                progress: snapshot.memory.usedPercent / 100,
                value: DisplayValueFormatter.percent(snapshot.memory.usedPercent),
                detail: "\(snapshot.memory.usedDisplay) used, \(snapshot.memory.availableDisplay) available",
                tint: memoryTint,
                accessibilityPrefix: "ram.used"
            )

            MetricLine(
                title: "Pressure",
                progress: snapshot.memory.pressurePercent / 100,
                value: DisplayValueFormatter.percent(snapshot.memory.pressurePercent),
                detail: "\(snapshot.memory.compressedDisplay) compressed",
                tint: memoryTint,
                accessibilityPrefix: "ram.pressure"
            )

            MemoryBreakdownView(memory: snapshot.memory, isExpanded: $isBreakdownExpanded)
        }
    }

    private var memoryTint: Color {
        switch snapshot.memory.status {
        case .normal: .accentIndigo
        case .elevated: .accentPlatinum
        case .high: .accentCopper
        }
    }
}

private struct MemoryBreakdownView: View {
    var memory: MemoryReading
    @Binding var isExpanded: Bool

    private var items: [MemoryBreakdownItem] {
        memory.breakdown.filter { $0.bytes > 0 }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 10) {
                MemoryBreakdownBar(items: items, totalBytes: memory.totalBytes)
                    .frame(height: 18)
                    .accessibilityIdentifier("ram.breakdown.bar")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(items) { item in
                        MemoryBreakdownLegendItem(item: item, totalBytes: memory.totalBytes)
                    }
                }

                MemoryProcessList(processes: memory.topProcesses)
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.secondaryText)
                Text("RAM breakdown")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primaryText.opacity(0.92))
                Spacer()
                Text("\(memory.availableDisplay) available")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .disclosureGroupStyle(.automatic)
        .tint(Color.secondaryText)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.controlSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                )
        )
        .accessibilityIdentifier("ram.breakdown")
        .accessibilityLabel("RAM breakdown. \(memory.usedDisplay) used, \(memory.availableDisplay) available.")
    }
}

private struct MemoryProcessList: View {
    var processes: [MemoryProcessReading]
    @State private var expandedGroupIDs: Set<String> = []

    private var groups: [MemoryProcessGroup] {
        Array(MemoryProcessGroup.make(from: processes).prefix(6))
    }

    private var largestResidentBytes: UInt64 {
        groups.map(\.residentBytes).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Top memory users")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primaryText.opacity(0.92))
                Spacer()
                Text("Resident memory")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.top, 2)

            if groups.isEmpty {
                Text("Process memory is unavailable right now.")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                    .padding(.vertical, 2)
            } else {
                VStack(spacing: 6) {
                    ForEach(groups) { group in
                        MemoryProcessGroupRow(
                            group: group,
                            largestResidentBytes: largestResidentBytes,
                            isExpanded: expandedGroupIDs.contains(group.id),
                            toggleExpanded: {
                                withAnimation(.snappy(duration: 0.18)) {
                                    if expandedGroupIDs.contains(group.id) {
                                        expandedGroupIDs.remove(group.id)
                                    } else {
                                        expandedGroupIDs.insert(group.id)
                                    }
                                }
                            }
                        )
                    }
                }
            }
        }
    }
}

private struct MemoryProcessGroup: Identifiable {
    var id: String
    var name: String
    var commandPath: String?
    var bundleIdentifier: String?
    var residentBytes: UInt64
    var processes: [MemoryProcessReading]
    var firstSeenIndex: Int

    var display: String {
        Self.memoryFormatter.string(fromByteCount: Int64(residentBytes))
    }

    private static var memoryFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .memory
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

    static func make(from processes: [MemoryProcessReading]) -> [MemoryProcessGroup] {
        let indexed = processes.enumerated().map { index, process in
            (index: index, process: process)
        }
        let byPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        var buckets: [String: (name: String, commandPath: String?, bundleIdentifier: String?, firstSeenIndex: Int, processes: [MemoryProcessReading])] = [:]

        for item in indexed {
            let grouping = groupDescriptor(for: item.process, byPID: byPID)
            var bucket = buckets[grouping.key] ?? (
                name: grouping.name,
                commandPath: grouping.commandPath,
                bundleIdentifier: grouping.bundleIdentifier,
                firstSeenIndex: item.index,
                processes: []
            )
            bucket.firstSeenIndex = min(bucket.firstSeenIndex, item.index)
            if bucket.commandPath == nil {
                bucket.commandPath = grouping.commandPath
            }
            if bucket.bundleIdentifier == nil {
                bucket.bundleIdentifier = grouping.bundleIdentifier
            }
            bucket.processes.append(item.process)
            buckets[grouping.key] = bucket
        }

        return buckets.map { key, bucket in
            let sortedProcesses = bucket.processes.sorted {
                if $0.residentBytes == $1.residentBytes {
                    return $0.pid < $1.pid
                }
                return $0.residentBytes > $1.residentBytes
            }
            return MemoryProcessGroup(
                id: key,
                name: bucket.name,
                commandPath: bucket.commandPath,
                bundleIdentifier: bucket.bundleIdentifier,
                residentBytes: sortedProcesses.reduce(UInt64(0)) { $0 + $1.residentBytes },
                processes: sortedProcesses,
                firstSeenIndex: bucket.firstSeenIndex
            )
        }
        .sorted {
            if $0.residentBytes == $1.residentBytes {
                return $0.firstSeenIndex < $1.firstSeenIndex
            }
            return $0.residentBytes > $1.residentBytes
        }
    }

    private static func groupDescriptor(
        for process: MemoryProcessReading,
        byPID: [Int32: MemoryProcessReading]
    ) -> (key: String, name: String, commandPath: String?, bundleIdentifier: String?) {
        if let commandPath = process.commandPath,
           let bundle = appBundle(for: commandPath) {
            return (
                key: bundle.identifier.map { "bundle:\($0)" } ?? "app:\(bundle.path)",
                name: bundle.name,
                commandPath: bundle.path,
                bundleIdentifier: bundle.identifier
            )
        }

        if let parentPid = process.parentPid,
           let parent = byPID[parentPid],
           let commandPath = parent.commandPath,
           let bundle = appBundle(for: commandPath) {
            return (
                key: bundle.identifier.map { "bundle:\($0)" } ?? "parent-app:\(bundle.path)",
                name: bundle.name,
                commandPath: bundle.path,
                bundleIdentifier: bundle.identifier
            )
        }

        if let commonName = commonParentName(for: process.name) {
            return (key: "common:\(commonName)", name: commonName, commandPath: nil, bundleIdentifier: nil)
        }

        return (key: "process:\(process.pid)", name: process.name, commandPath: process.commandPath, bundleIdentifier: nil)
    }

    private static func appBundle(for path: String) -> (path: String, name: String, identifier: String?)? {
        let url = URL(fileURLWithPath: path)
        let components = url.pathComponents
        guard let appIndex = components.firstIndex(where: { $0.hasSuffix(".app") }) else {
            return nil
        }

        // Use the outermost app bundle so nested helper apps are grouped under
        // their parent application, e.g. Chrome.app/.../Google Chrome Helper.app.
        let bundlePath = NSString.path(withComponents: Array(components[0...appIndex]))
        let bundleURL = URL(fileURLWithPath: bundlePath)
        let bundleName = bundleURL.deletingPathExtension().lastPathComponent
        return (bundlePath, bundleName, Bundle(url: bundleURL)?.bundleIdentifier)
    }

    private static func commonParentName(for name: String) -> String? {
        if name.hasPrefix("Google Chrome Helper") {
            return "Google Chrome"
        }
        if name.hasPrefix("ChatGPT Atlas ") || name.hasPrefix("ChatGPT Atlas(") {
            return "ChatGPT Atlas"
        }
        if name.hasPrefix("Codex Helper") {
            return "Codex"
        }
        if name.hasPrefix("Microsoft Edge Helper") {
            return "Microsoft Edge"
        }
        if name.hasPrefix("Brave Browser Helper") {
            return "Brave Browser"
        }
        if name.hasPrefix("Arc Helper") {
            return "Arc"
        }
        if name.hasPrefix("Safari Web Content") || name.hasPrefix("com.apple.WebKit") {
            return "Safari"
        }
        for suffix in [" (Renderer)", " (Service)", " (GPU)", " (Plugin)"] where name.hasSuffix(suffix) {
            return String(name.dropLast(suffix.count))
        }
        if name.hasSuffix(" Helper") {
            return String(name.dropLast(" Helper".count))
        }
        return nil
    }
}

private struct MemoryProcessGroupRow: View {
    var group: MemoryProcessGroup
    var largestResidentBytes: UInt64
    var isExpanded: Bool
    var toggleExpanded: () -> Void

    private var isExpandable: Bool {
        group.processes.count > 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 9) {
                ProcessIcon(commandPath: group.commandPath, name: group.name)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        if isExpandable {
                            Button(action: toggleExpanded) {
                                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .frame(width: 10, height: 10)
                                    .foregroundStyle(Color.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help(isExpanded ? "Hide processes" : "Show processes")
                        } else {
                            Color.clear
                                .frame(width: 10, height: 10)
                        }

                        Text(group.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(Color.primaryText.opacity(0.92))
                            .lineLimit(1)

                        if isExpandable {
                            Text("\(group.processes.count)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color.secondaryText)
                                .monospacedDigit()
                                .padding(.horizontal, 5.5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule()
                                        .fill(Color.primaryText.opacity(0.06))
                                        .overlay(
                                            Capsule()
                                                .stroke(Color.hairline, lineWidth: 1)
                                        )
                                )
                                .hoverTooltip(processCountTooltip)
                        }

                        // TODO: Track NSWorkspace activation history and show an inactive badge
                        // when this app has not been frontmost for 30 minutes and uses over 500 MB.
                    }

                    RelativeMemoryBar(value: barShare)
                        .frame(height: 4)
                        .help(helpText)
                }

                Spacer(minLength: 8)
                MemoryValueText(display: group.display)
                    .frame(minWidth: 76, alignment: .trailing)
            }

            if isExpanded && group.processes.count > 1 {
                VStack(spacing: 5) {
                    Rectangle()
                        .fill(Color.hairline.opacity(0.65))
                        .frame(height: 1)
                        .padding(.leading, 31)
                    VStack(spacing: 4) {
                        ForEach(group.processes) { process in
                            MemoryProcessChildRow(process: process)
                        }
                    }
                    .padding(.leading, 31)
                    .padding(.trailing, 2)
                }
                .padding(.top, 1)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(isExpanded ? 0.04 : 0.026))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.hairline.opacity(isExpanded ? 1 : 0.75), lineWidth: 1)
                )
        )
        .help(helpText)
        .accessibilityLabel("\(group.name), \(group.display). \(group.processes.count) processes.")
    }

    private var barShare: Double {
        guard largestResidentBytes > 0, group.residentBytes > 0 else {
            return 0
        }
        return min(max(Double(group.residentBytes) / Double(largestResidentBytes), 0.04), 1)
    }

    private var helpText: String {
        if group.processes.count == 1 {
            let process = group.processes[0]
            return "\(group.name) is using \(group.display) of resident memory. PID \(process.pid). \(process.commandPath ?? "System process")"
        }
        return "\(group.name) is using \(group.display) of resident memory across \(group.processes.count) processes."
    }

    private var processCountTooltip: String {
        group.processes.count == 1 ? "1 process" : "\(group.processes.count) processes"
    }
}

private struct MemoryProcessChildRow: View {
    var process: MemoryProcessReading

    var body: some View {
        HStack(spacing: 6) {
            Text(process.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
            Text("PID \(process.pid)")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.secondaryText.opacity(0.7))
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            MemoryValueText(display: process.display, numberSize: 10, unitSize: 8.5, numberWeight: .semibold)
                .frame(minWidth: 62, alignment: .trailing)
        }
        .accessibilityLabel("\(process.name), PID \(process.pid), \(process.display)")
    }
}

private struct MemoryValueText: View {
    var display: String
    var numberSize: CGFloat = 12
    var unitSize: CGFloat = 9.5
    var numberWeight: Font.Weight = .bold

    private var parts: (number: String, unit: String) {
        let split = display.split(separator: " ", maxSplits: 1).map(String.init)
        guard split.count == 2 else {
            return (display, "")
        }
        return (split[0], split[1])
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(parts.number)
                .font(.system(size: numberSize, weight: numberWeight))
                .foregroundStyle(Color.primaryText.opacity(0.92))
                .monospacedDigit()
            if !parts.unit.isEmpty {
                Text(parts.unit)
                    .font(.system(size: unitSize, weight: .semibold))
                    .foregroundStyle(Color.secondaryText.opacity(0.9))
            }
        }
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct RelativeMemoryBar: View {
    var value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primaryText.opacity(0.08))
                Capsule()
                    .fill(Color.accentIndigo)
                    .frame(width: fillWidth(in: geometry.size.width))
            }
        }
    }

    private func fillWidth(in availableWidth: CGFloat) -> CGFloat {
        guard value > 0 else {
            return 0
        }
        return max(availableWidth * CGFloat(min(value, 1)), availableWidth * 0.04)
    }
}

private struct ProcessIcon: View {
    var commandPath: String?
    var name: String

    var body: some View {
        if let image = icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentIndigo.opacity(0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.accentIndigo.opacity(0.25), lineWidth: 1)
                    )
                Text(initial)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Color.accentIndigo)
            }
            .frame(width: 22, height: 22)
        }
    }

    private var icon: NSImage? {
        guard let commandPath else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appBundlePath(for: commandPath) ?? commandPath)
    }

    private var initial: String {
        String(name.prefix(1)).uppercased()
    }

    private func appBundlePath(for path: String) -> String? {
        guard let range = path.range(of: ".app/") else {
            return nil
        }
        return String(path[..<range.lowerBound]) + ".app"
    }
}

private struct MemoryBreakdownBar: View {
    var items: [MemoryBreakdownItem]
    var totalBytes: UInt64

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                ForEach(items) { item in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(item.category.color)
                        .frame(width: segmentWidth(for: item, availableWidth: proxy.size.width))
                        .help(helpText(for: item))
                        .accessibilityLabel("\(item.category.label), \(item.display), \(percentText(for: item))")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
        }
    }

    private func segmentWidth(for item: MemoryBreakdownItem, availableWidth: CGFloat) -> CGFloat {
        guard totalBytes > 0 else { return 0 }
        let ratio = Double(item.bytes) / Double(totalBytes)
        return max(item.bytes > 0 ? 2 : 0, availableWidth * ratio)
    }

    private func percentText(for item: MemoryBreakdownItem) -> String {
        guard totalBytes > 0 else { return "0%" }
        return DisplayValueFormatter.percent(Double(item.bytes) / Double(totalBytes) * 100)
    }

    private func helpText(for item: MemoryBreakdownItem) -> String {
        "\(item.category.label): \(item.display) (\(percentText(for: item))). \(item.category.explanation)"
    }
}

private struct MemoryBreakdownLegendItem: View {
    var item: MemoryBreakdownItem
    var totalBytes: UInt64

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(item.category.color)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(item.category.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.primaryText.opacity(0.9))
                    Text(percentText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                }
                Text(item.display)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .hoverTooltip(item.category.tooltipText)
        .accessibilityLabel("\(item.category.label), \(item.display), \(percentText). \(item.category.explanation)")
    }

    private var percentText: String {
        guard totalBytes > 0 else { return "0%" }
        return DisplayValueFormatter.percent(Double(item.bytes) / Double(totalBytes) * 100)
    }
}

private struct HoverTooltipModifier: ViewModifier {
    var text: String
    var delay: TimeInterval = 0.4

    @State private var isHovering = false
    @State private var isVisible = false
    @State private var pendingShow: DispatchWorkItem?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    let showBelow = proxy.frame(in: .global).minY < 62
                    HoverTooltipBubble(text: text)
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? (showBelow ? 8 : -8) : (showBelow ? 2 : -2))
                        .animation(.easeOut(duration: 0.12), value: isVisible)
                        .allowsHitTesting(false)
                        .frame(width: 220)
                        .fixedSize(horizontal: false, vertical: true)
                        .position(x: proxy.size.width / 2, y: showBelow ? proxy.size.height + 8 : -8)
                }
                .frame(width: 220, height: 1)
                .zIndex(10)
            }
            .onHover { hovering in
                isHovering = hovering
                pendingShow?.cancel()

                if hovering {
                    let workItem = DispatchWorkItem {
                        if isHovering {
                            isVisible = true
                        }
                    }
                    pendingShow = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
                } else {
                    isVisible = false
                }
            }
    }
}

private struct HoverTooltipBubble: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(Color.primaryText.opacity(0.94))
            .lineSpacing(2)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.tooltipSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color.hairline, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.28), radius: 10, x: 0, y: 6)
            )
    }
}

private extension View {
    func hoverTooltip(_ text: String, delay: TimeInterval = 0.4) -> some View {
        modifier(HoverTooltipModifier(text: text, delay: delay))
    }
}

private extension MemoryCategory {
    var color: Color {
        switch self {
        case .active: .accentIndigo
        case .wired: .accentCopper
        case .compressed: .accentPlatinum
        case .cached: .accentSage
        case .free: Color.secondaryText.opacity(0.55)
        }
    }

    var tooltipText: String {
        switch self {
        case .active:
            "Memory currently being used by running apps. This is the memory that's actively doing work."
        case .wired:
            "Memory required by the system that can't be moved or compressed. Essential for macOS to run."
        case .compressed:
            "Inactive memory that macOS has compressed to save space. It's still usable but takes less room."
        case .cached:
            "Files macOS is keeping in memory in case you need them again. This will be released automatically when other apps need the space, so it's effectively free."
        case .free:
            "Memory not currently in use. macOS tries to keep this low because unused RAM is wasted RAM."
        }
    }
}

private struct ThermalsSection: View {
    var snapshot: HardwareSnapshot
    var unit: TemperatureUnit

    var body: some View {
        MetricGroup(
            title: "Thermals",
            pill: thermalsPill,
            systemImage: "thermometer.medium",
            tint: .accentCopper
        ) {
            if snapshot.thermals.isEmpty {
                EmptyMetricLine(
                    title: "CPU temperature",
                    value: thermalsEmptyValue,
                    detail: thermalsEmptyDetail,
                    accessibilityPrefix: "thermals.empty"
                )
            } else {
                ForEach(snapshot.thermals) { thermal in
                    let celsius = thermal.celsius ?? 0
                    MetricLine(
                        title: thermal.label,
                        progress: min(max(celsius / 100, 0), 1),
                        value: DisplayValueFormatter.temperature(thermal.celsius, unit: unit),
                        detail: thermal.source,
                        tint: celsius > 78 ? .accentCopper : .accentSage,
                        helpText: thermalHelp(for: thermal.label),
                        accessibilityPrefix: "thermal.\(thermal.label.lowercased())"
                    )
                }
            }
        }
    }

    private func thermalHelp(for label: String) -> String? {
        switch label {
        case "SoC":
            "System-on-Chip package temperature. This reflects the M-series chip area that contains CPU, GPU, media engines, and memory fabric."
        case "Die":
            "Internal silicon die sensor. This is usually hotter than the outer package and is the best early signal for thermal throttling."
        default:
            nil
        }
    }

    private var thermalsPill: String {
        if snapshot.cpu.modelName == "Loading" {
            return "Sampling"
        }
        return snapshot.thermals.isEmpty ? "Unsupported" : "SMC"
    }

    private var thermalsEmptyValue: String {
        snapshot.cpu.modelName == "Loading" ? "Sampling" : "Unsupported"
    }

    private var thermalsEmptyDetail: String {
        if snapshot.cpu.modelName == "Loading" {
            return "Temperature readings will appear after the first sample."
        }
        return "CPU temperature is unavailable without compatible SMC thermal keys."
    }
}

private struct BottleneckSection: View {
    var snapshot: HardwareSnapshot
    var unit: TemperatureUnit

    var body: some View {
        MetricGroup(title: "Slowdown", pill: severityLabel, systemImage: iconName, tint: tint) {
            HStack(alignment: .top, spacing: 11) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.16))
                        .frame(width: 34, height: 34)
                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(snapshot.bottleneck.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Color.primaryText)
                            .accessibilityIdentifier("slowdown.title")
                        Spacer()
                        Text(DisplayValueFormatter.percent(snapshot.bottleneck.progress * 100))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(tint)
                            .accessibilityIdentifier("slowdown.percent")
                    }

                    PremiumProgressBar(progress: snapshot.bottleneck.progress, tint: tint)
                        .accessibilityIdentifier("slowdown.progress")

                    Text(displayDetail)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("slowdown.detail")
                        .accessibilityLabel("Slowdown detail: \(displayDetail)")
                }
            }
        }
    }

    private var displayDetail: String {
        guard snapshot.bottleneck.title == "Thermal limit",
              let hottest = snapshot.thermals.compactMap(\.celsius).max() else {
            return snapshot.bottleneck.detail
        }
        return DisplayValueFormatter.thermalLimitDetail(hottestCelsius: hottest, unit: unit)
    }

    private var severityLabel: String {
        switch snapshot.bottleneck.severity {
        case .normal: "Clear"
        case .notice: "Watch"
        case .warning: "Busy"
        case .critical: "Limit"
        }
    }

    private var tint: Color {
        switch snapshot.bottleneck.severity {
        case .normal: .accentSage
        case .notice: .accentPlatinum
        case .warning, .critical: .accentCopper
        }
    }

    private var iconName: String {
        switch snapshot.bottleneck.severity {
        case .normal: "checkmark"
        case .notice: "waveform.path.ecg"
        case .warning: "exclamationmark"
        case .critical: "flame"
        }
    }
}

private struct WarningsSection: View {
    var warnings: [String]
    var isSampling: Bool

    var body: some View {
        if isSampling {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color.secondaryText)
                Text("Taking first live sample")
                    .lineLimit(1)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
            .padding(.top, -4)
            .accessibilityLabel("Taking first live sample")
        } else if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(warnings, id: \.self) { warning in
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                        Text(warning)
                            .lineLimit(2)
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondaryText)
                }
            }
            .padding(.top, -4)
        }
    }
}

private struct SettingsSection: View {
    @Binding var refreshInterval: Double
    @Binding var temperatureUnitRaw: String
    @Binding var menuBarDisplayModeRaw: String
    @Binding var launchAtLogin: Bool
    var launchAtLoginError: String?

    var body: some View {
        MetricGroup(title: "Settings", pill: "Prefs", systemImage: "slider.horizontal.3", tint: .accentPlatinum) {
            VStack(spacing: 10) {
                SettingsRow(title: "Refresh", systemImage: "clock") {
                    PremiumSegmentedControl(
                        selection: $refreshInterval,
                        options: [
                            SegmentOption(label: "1s", value: 1.0),
                            SegmentOption(label: "3s", value: 3.0),
                            SegmentOption(label: "5s", value: 5.0),
                            SegmentOption(label: "10s", value: 10.0)
                        ],
                        accent: .accentPlatinum
                    )
                    .help("Choose how often Thermal Pilot reads local hardware metrics.")
                    .accessibilityIdentifier("settings.refresh")
                    .accessibilityLabel("Refresh interval \(Int(refreshInterval)) seconds")
                }

                SettingsRow(title: "Menu bar", systemImage: "menubar.rectangle") {
                    PremiumMenuButton(
                        title: MenuBarDisplayMode(rawValue: menuBarDisplayModeRaw)?.label ?? "CPU %",
                        systemImage: "chevron.up.chevron.down"
                    ) {
                        ForEach(MenuBarDisplayMode.allCases) { mode in
                            Button(mode.label) {
                                withAnimation(.smooth(duration: 0.18)) {
                                    menuBarDisplayModeRaw = mode.rawValue
                                }
                            }
                        }
                    }
                    .help("Choose which metric appears beside the menu-bar icon.")
                    .accessibilityIdentifier("settings.menuBar")
                    .accessibilityLabel("Menu bar display \(MenuBarDisplayMode(rawValue: menuBarDisplayModeRaw)?.label ?? "CPU percent")")
                }

                SettingsRow(title: "Temperature", systemImage: "thermometer.medium") {
                    PremiumSegmentedControl(
                        selection: $temperatureUnitRaw,
                        options: TemperatureUnit.allCases.map { SegmentOption(label: $0.label, value: $0.rawValue) },
                        accent: .accentCopper
                    )
                    .frame(width: 118)
                    .accessibilityIdentifier("settings.temperature")
                    .accessibilityLabel("Temperature unit \(TemperatureUnit(rawValue: temperatureUnitRaw)?.label ?? "C")")
                }

                SettingsRow(title: "Launch at login", systemImage: "power") {
                    PremiumToggle(isOn: $launchAtLogin, title: "Launch at login")
                        .accessibilityIdentifier("settings.launchAtLogin")
                }

                if let launchAtLoginError {
                    InlineWarning(text: launchAtLoginError)
                }

                SettingsRow(title: "App", systemImage: "power.circle") {
                    Button {
                        NSApplication.shared.terminate(nil)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                            Text("Quit Thermal Pilot")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(Color.primaryText)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.controlBase)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .stroke(Color.hairline, lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(SettingsPressButtonStyle())
                    .help("Quit Thermal Pilot.")
                    .accessibilityIdentifier("settings.quit")
                }
            }
        }
    }
}

private struct SettingsRow<Control: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.secondaryText.opacity(0.9))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primaryText.opacity(0.92))
                    .frame(width: 102, alignment: .leading)
            }

            Spacer(minLength: 6)
            control
        }
        .frame(minHeight: 30)
    }
}

private struct InlineWarning: View {
    var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .bold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.accentCopper)
        .padding(.vertical, 2)
        .accessibilityLabel(text)
    }
}

private struct SegmentOption<Value: Hashable>: Identifiable {
    var label: String
    var value: Value
    var id: Value { value }
}

private struct PremiumSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    var options: [SegmentOption<Value>]
    var accent: Color
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 1) {
            ForEach(options) { option in
                Button {
                    withAnimation(.snappy(duration: 0.22)) {
                        selection = option.value
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(selection == option.value ? Color.segmentText : Color.secondaryText)
                        .frame(minWidth: 34)
                        .frame(height: 26)
                        .background {
                            if selection == option.value {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(
                                        LinearGradient(
                                            colors: [accent.opacity(0.9), accent.opacity(0.72)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .matchedGeometryEffect(id: "selected", in: namespace)
                                    .shadow(color: accent.opacity(0.2), radius: 8, y: 2)
                            }
                        }
                }
                .buttonStyle(SettingsPressButtonStyle())
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.controlBase)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.hairline, lineWidth: 1)
                )
        )
    }
}

private struct PremiumMenuButton<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.secondaryText)
            }
            .padding(.horizontal, 11)
            .frame(width: 154, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.controlBase)
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.hairline, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.button)
        .buttonStyle(SettingsPressButtonStyle())
    }
}

private struct PremiumToggle: View {
    @Binding var isOn: Bool
    var title: String

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.22)) {
                isOn.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(isOn ? Color.accentSage.opacity(0.72) : Color.controlBase)
                        .overlay(Capsule().stroke(Color.hairline, lineWidth: 1))
                    Circle()
                        .fill(isOn ? Color.segmentText : Color.secondaryText.opacity(0.6))
                        .frame(width: 14, height: 14)
                        .padding(3)
                        .shadow(color: .black.opacity(0.24), radius: 3, y: 1)
                }
                .frame(width: 36, height: 20)

                Text(title)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isOn ? Color.primaryText : Color.secondaryText)
            }
        }
        .buttonStyle(SettingsPressButtonStyle())
    }
}

private struct SettingsPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.965 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.smooth(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MetricGroup<Content: View>: View {
    var title: String
    var pill: String
    var systemImage: String
    var tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(tint.opacity(0.24), lineWidth: 1)
                        )
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .bold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(tint)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(Color.primaryText)
                        .accessibilityIdentifier("section.\(title.qaIdentifier).title")
                }

                Spacer()
                Text(pill)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.primaryText.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.055))
                            .overlay(Capsule().stroke(tint.opacity(0.22), lineWidth: 1))
                    )
                    .accessibilityIdentifier("section.\(title.qaIdentifier).pill")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.07), Color.white.opacity(0.015)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )

            content
        }
        .padding(.top, 4)
        .padding(.bottom, 24)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.hairline.opacity(0.72))
                .frame(height: 1)
        }
    }
}

private struct MetricLine: View {
    var title: String
    var progress: Double
    var value: String
    var progressLabel: String?
    var detail: String
    var tint: Color
    var helpText: String?
    var accessibilityPrefix: String

    init(
        title: String,
        progress: Double,
        value: String,
        progressLabel: String? = nil,
        detail: String,
        tint: Color,
        helpText: String? = nil,
        accessibilityPrefix: String
    ) {
        self.title = title
        self.progress = progress
        self.value = value
        self.progressLabel = progressLabel
        self.detail = detail
        self.tint = tint
        self.helpText = helpText
        self.accessibilityPrefix = accessibilityPrefix
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 5) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color.primaryText)
                        .accessibilityIdentifier("\(accessibilityPrefix).title")
                    if let helpText {
                        HelpBadge(text: helpText)
                            .accessibilityIdentifier("\(accessibilityPrefix).help")
                    }
                }
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.primaryText)
                    .accessibilityIdentifier("\(accessibilityPrefix).value")
                    .accessibilityLabel("\(title) value \(value)")
            }

            PremiumProgressBar(progress: progress, tint: progress > 0.78 ? .accentCopper : tint)
                .accessibilityIdentifier("\(accessibilityPrefix).progress")

            HStack {
                Text(progressText)
                    .accessibilityIdentifier("\(accessibilityPrefix).percent")
                Spacer()
                Text(detail)
                    .accessibilityIdentifier("\(accessibilityPrefix).detail")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value), \(progressText), \(detail)")
    }

    private var progressText: String {
        progressLabel ?? DisplayValueFormatter.percent(progress * 100)
    }
}

private struct HelpBadge: View {
    var text: String
    @State private var isHovering = false

    var body: some View {
        Image(systemName: "questionmark.circle.fill")
            .font(.system(size: 10, weight: .bold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isHovering ? Color.accentPlatinum : Color.secondaryText.opacity(0.72))
            .scaleEffect(isHovering ? 1.12 : 1)
            .help(text)
            .onHover { hovering in
                withAnimation(.smooth(duration: 0.14)) {
                    isHovering = hovering
                }
            }
    }
}

private struct EmptyMetricLine: View {
    var title: String
    var value: String
    var detail: String
    var accessibilityPrefix: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.primaryText)
                    .accessibilityIdentifier("\(accessibilityPrefix).title")
                Spacer()
                Text(value)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Color.secondaryText)
                    .accessibilityIdentifier("\(accessibilityPrefix).value")
            }
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.track)
                .frame(height: 8)
                .accessibilityIdentifier("\(accessibilityPrefix).progress")
            Text(detail)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.secondaryText)
                .accessibilityIdentifier("\(accessibilityPrefix).detail")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value). \(detail)")
    }
}

private struct PremiumProgressBar: View {
    var progress: Double
    var tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.track)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.92), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(8, proxy.size.width * min(max(progress, 0), 1)))
                    .shadow(color: tint.opacity(0.15), radius: 6, y: 1)
            }
        }
        .frame(height: 8)
        .animation(.smooth(duration: 0.38), value: progress)
    }
}

private struct Footer: View {
    var nextRefreshSeconds: Int
    var lastPublishedAt: Date?
    var isStale: Bool
    var refresh: () -> Void

    var body: some View {
        HStack {
            Text("Thermal Pilot 0.1.0")
                .accessibilityIdentifier("footer.version")
            Spacer()
            if isStale {
                Text("Reading delayed")
                    .foregroundStyle(Color.accentCopper)
                    .accessibilityIdentifier("footer.stale")
                    .help("The last hardware read took longer than expected for the selected refresh interval.")
            }
            Button(action: refresh) {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(FooterButtonStyle())
            .accessibilityIdentifier("footer.refresh")
            .accessibilityLabel("Refresh now")
            Text(lastUpdatedText)
                .accessibilityIdentifier("footer.lastUpdated")
            Text("Next update in \(nextRefreshSeconds)s")
                .accessibilityIdentifier("footer.nextRefresh")
        }
        .font(.system(size: 11, weight: .bold))
        .foregroundStyle(Color.secondaryText)
        .padding(.bottom, 4)
    }

    private var lastUpdatedText: String {
        guard let lastPublishedAt else {
            return "Sampling"
        }
        return "Updated \(lastPublishedAt.formatted(.dateTime.hour().minute().second()))"
    }
}

private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? Color.primaryText : Color.secondaryText)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.14), value: configuration.isPressed)
    }
}

private extension Color {
    static let panelBackground = Color(red: 0.076, green: 0.079, blue: 0.09)
    static let sidebarBackground = Color(red: 0.041, green: 0.044, blue: 0.052)
    static let primaryText = Color(red: 0.925, green: 0.925, blue: 0.935)
    static let secondaryText = Color(red: 0.56, green: 0.565, blue: 0.595)
    static let accentPlatinum = Color(red: 0.78, green: 0.76, blue: 0.68)
    static let accentSage = Color(red: 0.52, green: 0.72, blue: 0.62)
    static let accentIndigo = Color(red: 0.47, green: 0.55, blue: 0.78)
    static let accentCopper = Color(red: 0.88, green: 0.53, blue: 0.32)
    static let hairline = Color.white.opacity(0.10)
    static let track = Color.white.opacity(0.095)
    static let controlSurface = Color.white.opacity(0.035)
    static let tooltipSurface = Color(red: 0.105, green: 0.108, blue: 0.122)
    static let controlBase = Color.white.opacity(0.075)
    static let segmentText = Color(red: 0.075, green: 0.078, blue: 0.086)
}

private extension String {
    var qaIdentifier: String {
        lowercased()
            .replacingOccurrences(of: " ", with: ".")
            .replacingOccurrences(of: "/", with: ".")
    }
}

#Preview("All sensors") {
    ContentView(model: MetricsModel(provider: PreviewProvider(snapshot: .previewFull)))
        .frame(width: 390, height: 650)
        .environment(\.temperatureUnit, .celsius)
}

#Preview("Unavailable sensors") {
    ContentView(model: MetricsModel(provider: PreviewProvider(snapshot: .previewUnavailable)))
        .frame(width: 390, height: 650)
        .environment(\.temperatureUnit, .celsius)
}

private struct PreviewProvider: HardwareMetricsProviding {
    var snapshot: HardwareSnapshot

    func snapshot() async -> HardwareSnapshot {
        snapshot
    }
}

private extension HardwareSnapshot {
    static let previewFull = HardwareSnapshot(
        fans: [
            FanReading(id: "0", name: "Left fan", currentRPM: 2480, minRPM: 1200, maxRPM: 5200),
            FanReading(id: "1", name: "Right fan", currentRPM: 2210, minRPM: 1200, maxRPM: 5200)
        ],
        cpu: CPUReading(modelName: "Apple M4 Pro", coreCount: 14, usagePercent: 41),
        memory: MemoryReading(totalBytes: 51_539_607_552, usedBytes: 31_000_000_000, compressedBytes: 3_200_000_000, pressurePercent: 66, status: .normal),
        thermals: [
            ThermalReading(label: "SoC", celsius: 54, source: "SMC Tp09"),
            ThermalReading(label: "Die", celsius: 82, source: "SMC Te05")
        ],
        bottleneck: BottleneckReading(title: "Cooling active", detail: "Fans and thermals are elevated, but still within range", severity: .notice, progress: 0.72)
    )

    static let previewUnavailable = HardwareSnapshot(
        fans: [],
        cpu: CPUReading(modelName: "Apple M4 Pro", coreCount: 14, usagePercent: 87),
        memory: MemoryReading(totalBytes: 51_539_607_552, usedBytes: 47_000_000_000, compressedBytes: 12_000_000_000, pressurePercent: 92, status: .high),
        thermals: [],
        bottleneck: BottleneckReading(title: "Memory pressure", detail: "47 GB of 48 GB used, 12 GB compressed", severity: .critical, progress: 0.92),
        availabilityWarnings: ["Fan sensors unavailable on this Mac or blocked by SMC permissions."]
    )
}
