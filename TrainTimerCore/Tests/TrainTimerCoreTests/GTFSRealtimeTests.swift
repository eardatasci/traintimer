import Foundation
import Testing
@testable import TrainTimerCore

struct ProtoReaderTests {
    @Test func readsMultiByteVarints() throws {
        var reader = ProtoReader(Data([0xAC, 0x02, 0x01]))
        #expect(try reader.readVarint() == 300)
        #expect(try reader.readVarint() == 1)
        #expect(reader.isAtEnd)
    }

    @Test func rejectsTruncatedInput() {
        var varint = ProtoReader(Data([0x80]))
        #expect(throws: ProtoReader.Error.truncated) { try varint.readVarint() }

        var string = ProtoReader(Data([0x05, 0x61]))  // claims 5 bytes, has 1
        #expect(throws: ProtoReader.Error.truncated) { try string.readString() }
    }

    @Test func rejectsGroupWireTypes() {
        var reader = ProtoReader(Data([0x0B]))  // field 1, wire type 3 (start group)
        #expect(throws: ProtoReader.Error.unsupportedWireType(3)) { try reader.nextField() }
    }
}

struct RealtimeFeedTests {
    @Test func decodesTripUpdatesAndSkipsEverythingElse() throws {
        var feed = ProtoWriter()
        feed.message(1) { header in
            header.string(1, "1.0")
            header.varint(3, 1_700_000_000)
        }
        feed.message(2) { entity in
            entity.string(1, "000001L")
            entity.message(3) { tripUpdate in
                tripUpdate.message(1) { trip in
                    trip.string(1, "123456_L..N")
                    trip.string(3, "20231114")
                    trip.string(5, "L")
                    trip.message(1001) { nyct in nyct.string(1, "0L 1234+ CAN/8AV") }  // NYCT extension
                }
                tripUpdate.message(2) { stopTime in
                    stopTime.message(3) { departure in departure.varint(2, 1_700_000_060) }
                    stopTime.string(4, "L06N")
                }
                tripUpdate.message(2) { stopTime in
                    stopTime.message(2) { arrival in
                        arrival.varint(1, 30)  // delay
                        arrival.varint(2, 1_700_000_180)
                    }
                    stopTime.message(3) { departure in departure.varint(2, 1_700_000_200) }
                    stopTime.string(4, "L03N")
                    stopTime.fixed32(99, 7)
                    stopTime.fixed64(98, 7)
                }
            }
        }
        feed.message(2) { entity in
            entity.string(1, "vehicle-only")
            entity.message(4) { vehicle in vehicle.varint(1, 5) }
        }

        let decoded = try RealtimeFeed(protobuf: feed.data)

        #expect(decoded.timestamp == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(decoded.tripUpdates == [
            TripUpdate(tripID: "123456_L..N", routeID: "L", stopTimes: [
                StopTimeUpdate(stopID: "L06N", departure: Date(timeIntervalSince1970: 1_700_000_060)),
                StopTimeUpdate(
                    stopID: "L03N",
                    arrival: Date(timeIntervalSince1970: 1_700_000_180),
                    departure: Date(timeIntervalSince1970: 1_700_000_200)
                ),
            ]),
        ])
        #expect(decoded.tripUpdates[0].stopTimes[0].time == Date(timeIntervalSince1970: 1_700_000_060))
        #expect(decoded.tripUpdates[0].stopTimes[1].time == Date(timeIntervalSince1970: 1_700_000_180))
    }

    @Test(arguments: ["gtfs-l", "gtfs-ace"])
    func decodesCapturedMTAFeeds(name: String) throws {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "pb", subdirectory: "Fixtures"))
        let feed = try RealtimeFeed(protobuf: Data(contentsOf: url))

        let timestamp = try #require(feed.timestamp)
        #expect(!feed.tripUpdates.isEmpty)
        for trip in feed.tripUpdates {
            #expect(!trip.routeID.isEmpty)
            for stopTime in trip.stopTimes {
                #expect(stopTime.stopID.count == 4)
                let time = try #require(stopTime.time)
                #expect(abs(time.timeIntervalSince(timestamp)) < 6 * 3600)
            }
        }
    }
}
