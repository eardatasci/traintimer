import AppKit
import Observation
import ServiceManagement
import TrainTimerCore

@MainActor
@Observable
final class AppModel {
    static let stationCount = 4
    static let searchRadius = 2_000.0  // meters, roughly a 25 minute walk
    static let refreshInterval: TimeInterval = 30  // the MTA feeds update about this often
    static let tickInterval: Duration = .seconds(10)

    private(set) var locationStatus: LocationProvider.Status = .locating
    private(set) var stations: [NearbyStation] = []
    private(set) var boards: [StationBoard] = []
    private(set) var now = Date()
    private(set) var lastUpdated: Date?
    /// Feeds that failed on the last refresh, out of how many were requested.
    private(set) var failedFeeds: (failed: Int, requested: Int) = (0, 0)
    private(set) var opensAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var availableUpdate: LatestRelease?

    private let directory: StationDirectory
    private let client = FeedClient()
    private let location = LocationProvider()
    private var selector = FeedSelector()
    private var tripUpdatesByFeed: [SubwayFeed: [TripUpdate]] = [:]
    private var isRefreshing = false
    private var lastUpdateCheck: Date?

    init() {
        guard let url = Bundle.main.url(forResource: "stations", withExtension: "csv"),
              let csv = try? String(contentsOf: url, encoding: .utf8),
              let directory = try? StationDirectory(csv: csv)
        else { fatalError("stations.csv is missing from the app bundle or unreadable") }
        self.directory = directory

        location.onChange = { [weak self] status in self?.locationChanged(status) }
        location.start()
        locationChanged(location.status)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }

        // The model lives as long as the app, so the loop never needs to stop.
        Task {
            while true {
                await tick()
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }

    /// Menu bar text for the nearest station, e.g. "L 4m · 6 5m".
    var menuBarSummary: String? {
        boards.first?.menuBarSummary(now: now)
    }

    func refreshIfStale(olderThan age: TimeInterval) async {
        if lastUpdated.map({ Date().timeIntervalSince($0) >= age }) ?? true {
            await refresh()
        }
    }

    func refresh() async {
        guard !isRefreshing, !stations.isEmpty else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let feeds = selector.feedsToFetch(for: stations, at: Date())
        let results = await client.fetch(feeds)
        let loaded = results.compactMapValues { try? $0.get() }
        selector.record(loaded, at: Date())

        failedFeeds = (results.count - loaded.count, results.count)
        // Feeds we no longer poll don't serve nearby stops; failed feeds keep their last data.
        tripUpdatesByFeed = tripUpdatesByFeed
            .filter { feeds.contains($0.key) }
            .merging(loaded.mapValues(\.tripUpdates)) { _, new in new }
        if !loaded.isEmpty {
            lastUpdated = Date()
        }
        rebuildBoards()
    }

    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("TrainTimer: couldn't update login item: \(error)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func tick() async {
        now = Date()
        rebuildBoards()
        await refreshIfStale(olderThan: Self.refreshInterval)
        if lastUpdateCheck.map({ now.timeIntervalSince($0) >= 24 * 3600 }) ?? true {
            lastUpdateCheck = now
            await checkForUpdate()
        }
    }

    /// Looks for a newer GitHub release. Failures (offline, no releases yet) are silent.
    private func checkForUpdate() async {
        var request = URLRequest(url: AppInfo.latestReleaseAPI, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(LatestRelease.self, from: data)
        else { return }
        availableUpdate = release.isNewer(than: AppInfo.version) ? release : nil
    }

    private func locationChanged(_ status: LocationProvider.Status) {
        locationStatus = status
        guard case .located(let coordinate) = status else { return }

        let previous = stations.map(\.id)
        stations = directory.nearestStations(to: coordinate, limit: Self.stationCount, within: Self.searchRadius)
        rebuildBoards()
        if stations.map(\.id) != previous {
            Task { await refresh() }
        }
    }

    private func rebuildBoards() {
        now = Date()
        boards = StationBoard.boards(
            for: stations,
            tripUpdates: tripUpdatesByFeed.values.flatMap { $0 },
            directory: directory,
            now: now
        )
    }
}
