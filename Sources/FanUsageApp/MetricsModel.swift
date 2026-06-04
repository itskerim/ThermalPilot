import FanUsageCore
import Foundation

@MainActor
final class MetricsModel: ObservableObject {
    @Published private(set) var snapshot = HardwareSnapshot.placeholder
    @Published private(set) var nextRefreshSeconds = 3
    @Published private(set) var lastPublishedAt: Date?
    @Published private(set) var lastRefreshDurationMilliseconds: Double = 0
    @Published private(set) var isLastRefreshStale = false

    private let provider: HardwareMetricsProviding
    private var refreshInterval: Double = 3
    private var refreshTask: Task<Void, Never>?
    private var isRefreshing = false

    init(provider: HardwareMetricsProviding) {
        self.provider = provider
    }

    func configure(refreshInterval: Double) {
        self.refreshInterval = max(refreshInterval, 1)
        nextRefreshSeconds = Int(self.refreshInterval)
    }

    func start() async {
        if refreshTask != nil {
            return
        }

        refreshTask = Task { [weak self] in
            await self?.refreshLoop()
        }
    }

    func refreshNow() {
        Task {
            await refresh()
        }
    }

    private func refreshLoop() async {
        while !Task.isCancelled {
            await refresh()

            let interval = max(Int(refreshInterval), 1)
            for remaining in stride(from: interval, through: 1, by: -1) {
                nextRefreshSeconds = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled {
                    return
                }
            }
        }
    }

    private func refresh() async {
        guard !isRefreshing else {
            return
        }

        isRefreshing = true
        let startedAt = Date()
        let nextSnapshot = await provider.snapshot()
        let endedAt = Date()
        snapshot = nextSnapshot
        lastPublishedAt = endedAt
        lastRefreshDurationMilliseconds = endedAt.timeIntervalSince(startedAt) * 1_000
        isLastRefreshStale = endedAt.timeIntervalSince(startedAt) > refreshInterval * 2
        isRefreshing = false
    }
}
