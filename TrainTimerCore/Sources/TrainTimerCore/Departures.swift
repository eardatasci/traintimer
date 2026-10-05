import Foundation

public struct Departure: Sendable, Equatable {
    public var routeID: String
    /// Platform the train leaves from, e.g. "L03N".
    public var stopID: String
    /// Platform where the train terminates, e.g. "L01N".
    public var destinationStopID: String
    public var time: Date

    public init(routeID: String, stopID: String, destinationStopID: String, time: Date) {
        self.routeID = routeID
        self.stopID = stopID
        self.destinationStopID = destinationStopID
        self.time = time
    }

    /// A train whose predicted time just passed is probably still at the platform.
    public static let boardingGrace: TimeInterval = 30

    /// Upcoming departures from any platform of `parentStopIDs` within `horizon`, soonest first.
    /// Trains terminating at the stop are skipped since you can't ride them anywhere.
    public static func upcoming(
        in tripUpdates: [TripUpdate],
        at parentStopIDs: Set<String>,
        after now: Date,
        within horizon: TimeInterval = .infinity
    ) -> [Departure] {
        let earliest = now.addingTimeInterval(-boardingGrace)
        let latest = now.addingTimeInterval(horizon)
        var departures: [Departure] = []
        for trip in tripUpdates {
            guard let terminal = trip.stopTimes.last else { continue }
            for stopTime in trip.stopTimes.dropLast() {
                guard parentStopIDs.contains(Stop.parentID(of: stopTime.stopID)),
                      let time = stopTime.time, time >= earliest, time <= latest
                else { continue }
                departures.append(Departure(
                    routeID: trip.routeID,
                    stopID: stopTime.stopID,
                    destinationStopID: terminal.stopID,
                    time: time
                ))
            }
        }
        return departures.sorted { $0.time < $1.time }
    }
}

/// All upcoming trains on one route to one destination, e.g. "L to 8 Av: 2, 7, 12 min".
public struct DepartureGroup: Sendable, Equatable, Identifiable {
    public var id: String { "\(routeID)>\(destinationStopID)" }
    public var routeID: String
    /// Parent stop ID of the terminal.
    public var destinationStopID: String
    public var destinationName: String
    public var times: [Date]

    public init(routeID: String, destinationStopID: String, destinationName: String, times: [Date]) {
        self.routeID = routeID
        self.destinationStopID = destinationStopID
        self.destinationName = destinationName
        self.times = times
    }

    /// Groups departures by route and destination, ordered by each group's next train.
    public static func grouping(_ departures: [Departure], directory: StationDirectory, timesPerGroup: Int) -> [DepartureGroup] {
        var groups: [DepartureGroup] = []
        var indexByKey: [String: Int] = [:]
        for departure in departures.sorted(by: { $0.time < $1.time }) {
            let destination = Stop.parentID(of: departure.destinationStopID)
            let key = "\(departure.routeID)>\(destination)"
            if let index = indexByKey[key] {
                if groups[index].times.count < timesPerGroup {
                    groups[index].times.append(departure.time)
                }
            } else {
                indexByKey[key] = groups.count
                groups.append(DepartureGroup(
                    routeID: departure.routeID,
                    destinationStopID: destination,
                    destinationName: directory.stop(id: destination)?.name ?? destination,
                    times: [departure.time]
                ))
            }
        }
        return groups
    }
}

public struct StationBoard: Sendable, Equatable, Identifiable {
    public var id: String { station.id }
    public var station: NearbyStation
    public var groups: [DepartureGroup]

    public init(station: NearbyStation, groups: [DepartureGroup]) {
        self.station = station
        self.groups = groups
    }

    public static func boards(
        for stations: [NearbyStation],
        tripUpdates: [TripUpdate],
        directory: StationDirectory,
        now: Date,
        timesPerGroup: Int = 3,
        horizon: TimeInterval = 60 * 60
    ) -> [StationBoard] {
        stations.map { station in
            let departures = Departure.upcoming(in: tripUpdates, at: Set(station.stops.map(\.id)), after: now, within: horizon)
            return StationBoard(
                station: station,
                groups: DepartureGroup.grouping(departures, directory: directory, timesPerGroup: timesPerGroup)
            )
        }
    }

    /// Whether a train at `time` leaves early enough to walk to the station and catch it.
    public func isCatchable(_ time: Date, now: Date) -> Bool {
        time.timeIntervalSince(now) >= TimeInterval(station.walkingMinutes * 60)
    }

    /// The menu bar text: the next catchable train on each of the first few routes,
    /// e.g. "L 4m · 6 5m". Direction is left to the dropdown to keep this glanceable.
    public func menuBarSummary(now: Date, limit: Int = 2) -> String? {
        let catchable = groups
            .compactMap { group in
                group.times.first { isCatchable($0, now: now) }.map { (symbol: RouteStyle(routeID: group.routeID).symbol, time: $0) }
            }
            .sorted { $0.time < $1.time }
        var seen = Set<String>()
        let next = catchable.filter { seen.insert($0.symbol).inserted }.prefix(limit)
        guard !next.isEmpty else { return nil }
        return next.map { "\($0.symbol) \(Self.minutesLabel(until: $0.time, now: now))" }
            .joined(separator: " · ")
    }

    /// Whole minutes until `time`, rounded down like platform countdown clocks: "now", "1m", "12m".
    public static func minutesLabel(until time: Date, now: Date) -> String {
        let minutes = Int(time.timeIntervalSince(now) / 60)
        return minutes <= 0 ? "now" : "\(minutes)m"
    }
}
