import FanUsageCore
import ServiceManagement
import SwiftUI

@main
struct FanUsageApp: App {
    init() {
        Diagnostics.runIfRequested()
    }

    @StateObject private var model = MetricsModel(provider: CompositeHardwareProvider())
    @AppStorage("refreshInterval") private var refreshInterval = 3.0
    @AppStorage("temperatureUnit") private var temperatureUnitRaw = TemperatureUnit.celsius.rawValue
    @AppStorage("menuBarDisplayMode") private var menuBarDisplayModeRaw = MenuBarDisplayMode.cpu.rawValue

    var body: some Scene {
        MenuBarExtra {
            ContentView(model: model)
                .frame(width: 390, height: 650)
                .task {
                    model.configure(refreshInterval: refreshInterval)
                    await model.start()
                }
                .onChange(of: refreshInterval) { _, newValue in
                    model.configure(refreshInterval: newValue)
                }
                .environment(\.temperatureUnit, TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius)
        } label: {
            MenuBarLabel(
                snapshot: model.snapshot,
                displayMode: MenuBarDisplayMode(rawValue: menuBarDisplayModeRaw) ?? .cpu,
                temperatureUnit: TemperatureUnit(rawValue: temperatureUnitRaw) ?? .celsius
            )
            .task {
                model.configure(refreshInterval: refreshInterval)
                await model.start()
            }
            .onChange(of: refreshInterval) { _, newValue in
                model.configure(refreshInterval: newValue)
            }
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    var snapshot: HardwareSnapshot
    var displayMode: MenuBarDisplayMode
    var temperatureUnit: TemperatureUnit

    var body: some View {
        switch displayMode {
        case .cpu:
            Label(DisplayValueFormatter.percent(snapshot.cpu.usagePercent), systemImage: "cpu")
        case .fan:
            Label(DisplayValueFormatter.compactRPM(snapshot.fans.compactMap(\.currentRPM).first), systemImage: "fan")
        case .temperature:
            Label(DisplayValueFormatter.temperature(snapshot.thermals.compactMap(\.celsius).first, unit: temperatureUnit), systemImage: "thermometer.medium")
        case .iconOnly:
            Image(systemName: "fan")
        }
    }
}
