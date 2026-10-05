import Foundation
import Testing
@testable import TrainTimerCore

func sampleDirectory() throws -> StationDirectory {
    let url = try #require(Bundle.module.url(forResource: "stations-sample", withExtension: "csv", subdirectory: "Fixtures"))
    return try StationDirectory(csv: String(contentsOf: url, encoding: .utf8))
}

struct CSVTests {
    @Test func handlesQuotesEscapesAndLineEndings() {
        let rows = CSV.parse("a,\"b, c\",\"say \"\"hi\"\"\"\r\nd,,\"multi\nline\"\n")
        #expect(rows == [["a", "b, c", "say \"hi\""], ["d", "", "multi\nline"]])
    }

    @Test func keepsLastRowWithoutTrailingNewline() {
        #expect(CSV.parse("a,b\nc,\"d\"") == [["a", "b"], ["c", "d"]])
    }
}

struct StationDirectoryTests {
    @Test func parsesMTAStationExport() throws {
        let directory = try sampleDirectory()
        let unionSquareL = try #require(directory.stop(id: "L03"))
        #expect(unionSquareL == Stop(
            id: "L03",
            complexID: "602",
            name: "14 St-Union Sq",
            routes: ["L"],
            coordinate: Coordinate(latitude: 40.734789, longitude: -73.99073)
        ))
        #expect(directory.stop(id: "R20")?.routes == ["N", "Q", "R", "W"])
        #expect(directory.stop(id: "L03N") == unionSquareL)
        #expect(directory.stop(id: "XYZ") == nil)
    }

    @Test func rejectsUnexpectedColumns() {
        #expect(throws: StationDirectory.Error.missingColumn("GTFS Stop ID")) {
            try StationDirectory(csv: "Stop,Name\nL03,Union Sq\n")
        }
    }

    @Test func groupsNearestStationsByComplex() throws {
        let directory = try sampleDirectory()
        // Corner of Broadway & E 14 St, just outside Union Square.
        let here = Coordinate(latitude: 40.7345, longitude: -73.9905)

        let stations = directory.nearestStations(to: here, limit: 3)

        #expect(stations.map(\.complexID) == ["602", "118", "601"])
        #expect(stations[0].name == "14 St-Union Sq")
        #expect(Set(stations[0].stops.map(\.id)) == ["L03", "635", "R20"])
        #expect(stations[0].distance < 50)
        #expect(stations[0].walkingMinutes == 1)
        #expect(stations[1].name == "3 Av")
        #expect((5...9).contains(stations[1].walkingMinutes))
    }

    @Test func nearestStationsRespectsMaxDistance() throws {
        let directory = try sampleDirectory()
        let tottenville = Coordinate(latitude: 40.5128, longitude: -74.2520)
        let stations = directory.nearestStations(to: tottenville, limit: 5, within: 2000)
        #expect(stations.map(\.complexID) == ["522"])
    }

    @Test func mixedNameComplexesUseTheNearestStopsName() throws {
        let stops = [
            Stop(id: "A36", complexID: "624", name: "Chambers St", routes: ["A", "C"], coordinate: Coordinate(latitude: 40.714111, longitude: -74.008585)),
            Stop(id: "E01", complexID: "624", name: "World Trade Center", routes: ["E"], coordinate: Coordinate(latitude: 40.712582, longitude: -74.009781)),
        ]
        let directory = StationDirectory(stops: stops)
        let nearWTC = Coordinate(latitude: 40.7124, longitude: -74.0099)
        #expect(directory.nearestStations(to: nearWTC, limit: 1).first?.name == "World Trade Center")
    }

    @Test func parsesCoordinateStrings() {
        #expect(Coordinate(string: "40.7359, -73.9906") == Coordinate(latitude: 40.7359, longitude: -73.9906))
        #expect(Coordinate(string: "40.7") == nil)
        #expect(Coordinate(string: "140,-73") == nil)
    }

    @Test func stripsOnlyDirectionSuffixes() {
        #expect(Stop.parentID(of: "L03N") == "L03")
        #expect(Stop.parentID(of: "S31S") == "S31")
        #expect(Stop.parentID(of: "S31") == "S31")
        #expect(Stop.parentID(of: "635") == "635")
    }
}
