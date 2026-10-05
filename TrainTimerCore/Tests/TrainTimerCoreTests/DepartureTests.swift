import Foundation
import Testing
@testable import TrainTimerCore

private let now = Date(timeIntervalSince1970: 1_700_000_000)

private func at(_ minutes: Double) -> Date {
    now.addingTimeInterval(minutes * 60)
}

private func trip(_ route: String, _ stops: [(String, Double)]) -> TripUpdate {
    TripUpdate(tripID: UUID().uuidString, routeID: route, stopTimes: stops.map { StopTimeUpdate(stopID: $0.0, arrival: at($0.1)) })
}

struct DepartureTests {
    @Test func listsUpcomingTrainsAtAnyPlatformSoonestFirst() {
        let trips = [
            trip("L", [("L06N", 1), ("L05N", 2), ("L03N", 4), ("L01N", 8)]),
            trip("L", [("L01S", -2), ("L03S", 2), ("L05S", 3), ("L29S", 40)]),
            trip("6", [("635N", 3), ("631N", 6), ("601N", 40)]),
        ]

        let departures = Departure.upcoming(in: trips, at: ["L03", "635"], after: now)

        #expect(departures == [
            Departure(routeID: "L", stopID: "L03S", destinationStopID: "L29S", time: at(2)),
            Departure(routeID: "6", stopID: "635N", destinationStopID: "601N", time: at(3)),
            Departure(routeID: "L", stopID: "L03N", destinationStopID: "L01N", time: at(4)),
        ])
    }

    @Test func skipsDepartedAndTerminatingTrains() {
        let trips = [
            trip("L", [("L05N", -3), ("L03N", -1), ("L01N", 3)]),     // left Union Sq a minute ago
            trip("L", [("L03N", -0.25), ("L01N", 4)]),               // at the platform now
            trip("L", [("L06N", 2), ("L03N", 5)]),                   // terminates at Union Sq
        ]

        let departures = Departure.upcoming(in: trips, at: ["L03"], after: now)

        #expect(departures.map(\.time) == [at(-0.25)])
    }

    @Test func ignoresTrainsBeyondTheHorizon() {
        let trips = [
            trip("R", [("R20N", 45), ("R01N", 70)]),
            trip("R", [("R20N", 85), ("R01N", 110)]),
        ]
        let departures = Departure.upcoming(in: trips, at: ["R20"], after: now, within: 60 * 60)
        #expect(departures.map(\.time) == [at(45)])
    }

    @Test func groupsByRouteAndDestination() throws {
        let directory = try sampleDirectory()
        let departures = [
            Departure(routeID: "L", stopID: "L03S", destinationStopID: "L29S", time: at(2)),
            Departure(routeID: "L", stopID: "L03N", destinationStopID: "L01N", time: at(3)),
            Departure(routeID: "L", stopID: "L03S", destinationStopID: "L29S", time: at(6)),
            Departure(routeID: "L", stopID: "L03S", destinationStopID: "L29S", time: at(9)),
            Departure(routeID: "L", stopID: "L03S", destinationStopID: "L29S", time: at(12)),
            Departure(routeID: "6", stopID: "635N", destinationStopID: "601N", time: at(4)),
        ]

        let groups = DepartureGroup.grouping(departures, directory: directory, timesPerGroup: 3)

        #expect(groups == [
            DepartureGroup(routeID: "L", destinationStopID: "L29", destinationName: "Canarsie-Rockaway Pkwy", times: [at(2), at(6), at(9)]),
            DepartureGroup(routeID: "L", destinationStopID: "L01", destinationName: "8 Av", times: [at(3)]),
            DepartureGroup(routeID: "6", destinationStopID: "601", destinationName: "601", times: [at(4)]),
        ])
    }

    @Test func buildsBoardsForEachNearbyStation() throws {
        let directory = try sampleDirectory()
        let stations = directory.nearestStations(to: Coordinate(latitude: 40.7345, longitude: -73.9905), limit: 2)
        let trips = [trip("L", [("L06N", 1), ("L05N", 2), ("L03N", 4), ("L01N", 8)])]

        let boards = StationBoard.boards(for: stations, tripUpdates: trips, directory: directory, now: now)

        #expect(boards.map(\.station.name) == ["14 St-Union Sq", "3 Av"])
        #expect(boards.map { $0.groups.map(\.times) } == [[[at(4)]], [[at(2)]]])
    }
}

struct MenuBarSummaryTests {
    private func board(walkingDistance: Double, groups: [DepartureGroup]) -> StationBoard {
        let station = NearbyStation(complexID: "602", name: "14 St-Union Sq", stops: [], distance: walkingDistance)
        return StationBoard(station: station, groups: groups)
    }

    @Test func showsNextCatchableTrainPerGroup() {
        let board = board(walkingDistance: 250, groups: [  // ~5 min walk
            DepartureGroup(routeID: "L", destinationStopID: "L01", destinationName: "8 Av", times: [at(2), at(7.5), at(12)]),
            DepartureGroup(routeID: "6X", destinationStopID: "601", destinationName: "Pelham Bay Park", times: [at(5.2)]),
            DepartureGroup(routeID: "N", destinationStopID: "R01", destinationName: "Astoria", times: [at(9)]),
        ])
        #expect(board.station.walkingMinutes == 5)
        #expect(board.menuBarSummary(now: now) == "6 5m · L 7m")
    }

    @Test func showsEachRouteOnceEvenWhenBothDirectionsAreDue() {
        let board = board(walkingDistance: 30, groups: [
            DepartureGroup(routeID: "Q", destinationStopID: "D43", destinationName: "Coney Island", times: [at(3)]),
            DepartureGroup(routeID: "Q", destinationStopID: "Q05", destinationName: "96 St", times: [at(3.5)]),
            DepartureGroup(routeID: "L", destinationStopID: "L01", destinationName: "8 Av", times: [at(5)]),
        ])
        #expect(board.menuBarSummary(now: now) == "Q 3m · L 5m")
    }

    @Test func isNilWhenNothingIsCatchable() {
        let board = board(walkingDistance: 250, groups: [
            DepartureGroup(routeID: "L", destinationStopID: "L01", destinationName: "8 Av", times: [at(1)]),
        ])
        #expect(board.menuBarSummary(now: now) == nil)
    }

    @Test func roundsMinutesDownLikePlatformClocks() {
        #expect(StationBoard.minutesLabel(until: at(-0.2), now: now) == "now")
        #expect(StationBoard.minutesLabel(until: at(0.9), now: now) == "now")
        #expect(StationBoard.minutesLabel(until: at(1.9), now: now) == "1m")
        #expect(StationBoard.minutesLabel(until: at(12), now: now) == "12m")
    }
}

struct RouteStyleTests {
    @Test func mapsMTARouteIDsToBullets() {
        #expect(RouteStyle(routeID: "6X") == RouteStyle(routeID: "6").with(isExpress: true))
        #expect(RouteStyle(routeID: "6").color == 0x009952)
        #expect(RouteStyle(routeID: "GS").symbol == "S")
        #expect(RouteStyle(routeID: "FS").symbol == "S")
        #expect(RouteStyle(routeID: "H").symbol == "S")
        #expect(RouteStyle(routeID: "SI").symbol == "SIR")
        #expect(RouteStyle(routeID: "Q").usesDarkText)
        #expect(!RouteStyle(routeID: "L").usesDarkText)
        #expect(!RouteStyle(routeID: "SI").isExpress)
    }
}

private extension RouteStyle {
    func with(isExpress: Bool) -> RouteStyle {
        var copy = self
        copy.isExpress = isExpress
        return copy
    }
}
