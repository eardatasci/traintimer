import Foundation

/// The parts of a GTFS-Realtime feed we care about: trip updates and their predicted stop times.
/// Field numbers follow https://gtfs.org/realtime/reference/ — everything else
/// (vehicle positions, alerts, NYCT extensions) is skipped.
public struct RealtimeFeed: Sendable, Equatable {
    public var timestamp: Date?
    public var tripUpdates: [TripUpdate]

    public init(timestamp: Date? = nil, tripUpdates: [TripUpdate]) {
        self.timestamp = timestamp
        self.tripUpdates = tripUpdates
    }

    public init(protobuf data: Data) throws {
        var reader = ProtoReader(data)
        var timestamp: Date?
        var tripUpdates: [TripUpdate] = []
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, .lengthDelimited):  // FeedMessage.header
                var header = try reader.readMessage()
                while let headerField = try header.nextField() {
                    if headerField == (3, .varint) {  // FeedHeader.timestamp
                        timestamp = Date(timeIntervalSince1970: TimeInterval(try header.readVarint()))
                    } else {
                        try header.skip(headerField.wireType)
                    }
                }
            case (2, .lengthDelimited):  // FeedMessage.entity
                var entity = try reader.readMessage()
                while let entityField = try entity.nextField() {
                    if entityField == (3, .lengthDelimited) {  // FeedEntity.trip_update
                        var message = try entity.readMessage()
                        tripUpdates.append(try TripUpdate(reading: &message))
                    } else {
                        try entity.skip(entityField.wireType)
                    }
                }
            default:
                try reader.skip(field.wireType)
            }
        }
        self.init(timestamp: timestamp, tripUpdates: tripUpdates)
    }
}

public struct TripUpdate: Sendable, Equatable {
    public var tripID: String
    public var routeID: String
    public var stopTimes: [StopTimeUpdate]

    public init(tripID: String, routeID: String, stopTimes: [StopTimeUpdate]) {
        self.tripID = tripID
        self.routeID = routeID
        self.stopTimes = stopTimes
    }

    fileprivate init(reading reader: inout ProtoReader) throws {
        var tripID = ""
        var routeID = ""
        var stopTimes: [StopTimeUpdate] = []
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (1, .lengthDelimited):  // TripUpdate.trip
                var trip = try reader.readMessage()
                while let tripField = try trip.nextField() {
                    switch (tripField.number, tripField.wireType) {
                    case (1, .lengthDelimited): tripID = try trip.readString()
                    case (5, .lengthDelimited): routeID = try trip.readString()
                    default: try trip.skip(tripField.wireType)
                    }
                }
            case (2, .lengthDelimited):  // TripUpdate.stop_time_update
                var message = try reader.readMessage()
                stopTimes.append(try StopTimeUpdate(reading: &message))
            default:
                try reader.skip(field.wireType)
            }
        }
        self.init(tripID: tripID, routeID: routeID, stopTimes: stopTimes)
    }
}

public struct StopTimeUpdate: Sendable, Equatable {
    /// Platform-level stop ID, e.g. "L03N".
    public var stopID: String
    public var arrival: Date?
    public var departure: Date?

    public init(stopID: String, arrival: Date? = nil, departure: Date? = nil) {
        self.stopID = stopID
        self.arrival = arrival
        self.departure = departure
    }

    /// When the train is at the platform. Origin stops only carry a departure.
    public var time: Date? { arrival ?? departure }

    fileprivate init(reading reader: inout ProtoReader) throws {
        var stopID = ""
        var arrival: Date?
        var departure: Date?
        while let field = try reader.nextField() {
            switch (field.number, field.wireType) {
            case (2, .lengthDelimited):
                var event = try reader.readMessage()
                arrival = try Self.readEventTime(&event)
            case (3, .lengthDelimited):
                var event = try reader.readMessage()
                departure = try Self.readEventTime(&event)
            case (4, .lengthDelimited):
                stopID = try reader.readString()
            default:
                try reader.skip(field.wireType)
            }
        }
        self.init(stopID: stopID, arrival: arrival, departure: departure)
    }

    /// Reads StopTimeEvent.time (field 2, POSIX seconds).
    private static func readEventTime(_ reader: inout ProtoReader) throws -> Date? {
        var time: Date?
        while let field = try reader.nextField() {
            if field == (2, .varint) {
                time = Date(timeIntervalSince1970: TimeInterval(Int64(bitPattern: try reader.readVarint())))
            } else {
                try reader.skip(field.wireType)
            }
        }
        return time
    }
}
