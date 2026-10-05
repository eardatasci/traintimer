import Foundation
import Testing
@testable import TrainTimerCore

struct SubwayFeedTests {
    private func stop(_ id: String, _ routes: String) -> Stop {
        Stop(id: id, complexID: id, name: id, routes: routes.split(separator: " ").map(String.init), coordinate: Coordinate(latitude: 0, longitude: 0))
    }

    @Test func mapsDaytimeRoutesToFeeds() {
        #expect(SubwayFeed.feeds(serving: [stop("R20", "N Q R W"), stop("635", "4 5 6"), stop("L03", "L")]) == [.nqrw, .numbered, .l])
        #expect(SubwayFeed.feeds(serving: [stop("A31", "A C E"), stop("D21", "B D F M")]) == [.ace, .bdfm])
        #expect(SubwayFeed.feeds(serving: [stop("S31", "SIR")]) == [.sir])
    }

    @Test func mapsEachShuttleToItsOwnFeed() {
        #expect(SubwayFeed.feeds(serving: [stop("902", "S")]) == [.numbered])
        #expect(SubwayFeed.feeds(serving: [stop("H15", "S")]) == [.ace])
        #expect(SubwayFeed.feeds(serving: [stop("S01", "S")]) == [.bdfm])
        #expect(SubwayFeed.feeds(serving: [stop("D26", "B Q S")]) == [.bdfm, .nqrw])
    }

    @Test func buildsMTAEndpointURLs() {
        #expect(SubwayFeed.nqrw.url.absoluteString == "https://api-endpoint.mta.info/Dataservice/mtagtfsfeeds/nyct%2Fgtfs-nqrw")
    }
}

struct FeedSelectorTests {
    private let start = Date(timeIntervalSince1970: 1_700_000_000)
    private let unionSquare = [NearbyStation(
        complexID: "602",
        name: "14 St-Union Sq",
        stops: [Stop(id: "L03", complexID: "602", name: "14 St-Union Sq", routes: ["L"], coordinate: Coordinate(latitude: 0, longitude: 0))],
        distance: 10
    )]

    private func feed(servingStop stopID: String) -> RealtimeFeed {
        RealtimeFeed(tripUpdates: [TripUpdate(tripID: "t", routeID: "X", stopTimes: [StopTimeUpdate(stopID: stopID)])])
    }

    @Test func sweepsEveryFeedFirstThenPollsDaytimeAndObservedFeeds() {
        var selector = FeedSelector(sweepInterval: 300)

        #expect(selector.feedsToFetch(for: unionSquare, at: start) == Set(SubwayFeed.allCases))
        // During a reroute the 6 shows up at the L platform; the numbered feed should stay in rotation.
        selector.record([.l: feed(servingStop: "L03N"), .numbered: feed(servingStop: "L03S"), .g: feed(servingStop: "G22N")], at: start)

        #expect(selector.feedsToFetch(for: unionSquare, at: start.addingTimeInterval(30)) == [.l, .numbered])
        #expect(selector.feedsToFetch(for: unionSquare, at: start.addingTimeInterval(300)) == Set(SubwayFeed.allCases))
    }

    @Test func sweepsAgainWhenNearbyStationsChange() {
        var selector = FeedSelector()
        _ = selector.feedsToFetch(for: unionSquare, at: start)
        selector.record([.l: feed(servingStop: "L03N")], at: start)

        #expect(selector.feedsToFetch(for: [], at: start.addingTimeInterval(10)) == Set(SubwayFeed.allCases))
    }

    @Test func aFailedFeedDuringASweepDoesNotForceAnotherSweep() {
        var selector = FeedSelector()
        _ = selector.feedsToFetch(for: unionSquare, at: start)
        selector.record([.l: feed(servingStop: "L03N")], at: start)  // seven feeds failed

        #expect(selector.feedsToFetch(for: unionSquare, at: start.addingTimeInterval(30)) == [.l])
    }
}
