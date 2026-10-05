import Foundation

/// The MTA publishes subway realtime data as one GTFS-RT feed per group of lines.
/// No API key is required. https://api.mta.info/#/subwayRealTimeFeeds
public enum SubwayFeed: String, CaseIterable, Sendable {
    case numbered = "gtfs"  // 1 2 3 4 5 6 7, 42 St shuttle
    case ace = "gtfs-ace"   // A C E, Rockaway Park shuttle (H)
    case bdfm = "gtfs-bdfm" // B D F M, Franklin Av shuttle (FS)
    case g = "gtfs-g"
    case jz = "gtfs-jz"
    case nqrw = "gtfs-nqrw"
    case l = "gtfs-l"
    case sir = "gtfs-si"

    public var url: URL {
        URL(string: "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2F\(rawValue)")!
    }

    /// Feeds carrying the daytime routes listed for `stops`.
    public static func feeds(serving stops: [Stop]) -> Set<SubwayFeed> {
        var feeds = Set<SubwayFeed>()
        for stop in stops {
            for route in stop.routes {
                switch route {
                case "1", "2", "3", "4", "5", "6", "7": feeds.insert(.numbered)
                case "A", "C", "E": feeds.insert(.ace)
                case "B", "D", "F", "M": feeds.insert(.bdfm)
                case "G": feeds.insert(.g)
                case "J", "Z": feeds.insert(.jz)
                case "N", "Q", "R", "W": feeds.insert(.nqrw)
                case "L": feeds.insert(.l)
                case "SIR": feeds.insert(.sir)
                // The MTA lists all three shuttles as "S": 42 St (stops 90x) is in the numbered
                // feed, Rockaway Park (Hxx) in ACE, and Franklin Av in BDFM.
                case "S":
                    if stop.id.hasPrefix("9") {
                        feeds.insert(.numbered)
                    } else if stop.id.hasPrefix("H") {
                        feeds.insert(.ace)
                    } else {
                        feeds.insert(.bdfm)
                    }
                default: break
                }
            }
        }
        return feeds
    }
}

/// Decides which feeds to poll. Daytime route lists miss late-night patterns, weekend
/// reroutes and diversions, so every few minutes we fetch every feed and then keep
/// polling whichever ones actually served the nearby stops.
public struct FeedSelector: Sendable {
    public var sweepInterval: TimeInterval

    private var stopIDs: Set<String> = []
    private var lastSweep: Date?
    private var observed: Set<SubwayFeed> = []
    private var sweepPending = false

    public init(sweepInterval: TimeInterval = 5 * 60) {
        self.sweepInterval = sweepInterval
    }

    public mutating func feedsToFetch(for stations: [NearbyStation], at now: Date) -> Set<SubwayFeed> {
        let stops = stations.flatMap(\.stops)
        let ids = Set(stops.map(\.id))
        if ids != stopIDs {
            stopIDs = ids
            lastSweep = nil
            observed = []
        }
        if let lastSweep, now.timeIntervalSince(lastSweep) < sweepInterval {
            sweepPending = false
            return SubwayFeed.feeds(serving: stops).union(observed)
        }
        sweepPending = true
        return Set(SubwayFeed.allCases)
    }

    /// Call with the feeds that loaded after the last `feedsToFetch`. A sweep resets the
    /// observed set (a feed that failed to load just isn't counted); regular polls never shrink it.
    public mutating func record(_ feeds: [SubwayFeed: RealtimeFeed], at now: Date) {
        let served = feeds.filter { _, feed in
            feed.tripUpdates.contains { trip in
                trip.stopTimes.contains { stopIDs.contains(Stop.parentID(of: $0.stopID)) }
            }
        }
        if sweepPending {
            sweepPending = false
            observed = Set(served.keys)
            lastSweep = now
        } else {
            observed.formUnion(served.keys)
        }
    }
}

public struct FeedClient: Sendable {
    public var session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetches feeds concurrently. Failed feeds are reported, not thrown, so one bad feed
    /// doesn't blank out every station.
    public func fetch(_ feeds: Set<SubwayFeed>) async -> [SubwayFeed: Result<RealtimeFeed, any Error>] {
        await withTaskGroup(of: (SubwayFeed, Result<RealtimeFeed, any Error>).self) { group in
            for feed in feeds {
                group.addTask {
                    do {
                        var request = URLRequest(url: feed.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
                        request.setValue("application/x-protobuf", forHTTPHeaderField: "Accept")
                        let (data, response) = try await session.data(for: request)
                        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                            throw URLError(.badServerResponse)
                        }
                        return (feed, .success(try RealtimeFeed(protobuf: data)))
                    } catch {
                        return (feed, .failure(error))
                    }
                }
            }
            var results: [SubwayFeed: Result<RealtimeFeed, any Error>] = [:]
            for await (feed, result) in group {
                results[feed] = result
            }
            return results
        }
    }
}
