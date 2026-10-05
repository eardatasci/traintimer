import Foundation

public struct Coordinate: Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Parses "lat,lon" (e.g. "40.7359,-73.9906").
    public init?(string: String) {
        let parts = string.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let latitude = parts[0], let longitude = parts[1],
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return nil }
        self.init(latitude: latitude, longitude: longitude)
    }

    /// Great-circle (haversine) distance in meters.
    public func distance(to other: Coordinate) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (other.latitude - latitude) * .pi / 180
        let dLon = (other.longitude - longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(latitude * .pi / 180) * cos(other.latitude * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }
}

/// One platform group in the MTA station list, e.g. the L at 14 St-Union Sq ("L03").
public struct Stop: Sendable, Equatable, Identifiable {
    /// GTFS parent stop ID; realtime feeds append "N"/"S" for direction.
    public var id: String
    public var complexID: String
    public var name: String
    /// Daytime routes as printed by the MTA, e.g. ["N", "Q", "R", "W"] or ["SIR"].
    public var routes: [String]
    public var coordinate: Coordinate

    public init(id: String, complexID: String, name: String, routes: [String], coordinate: Coordinate) {
        self.id = id
        self.complexID = complexID
        self.name = name
        self.routes = routes
        self.coordinate = coordinate
    }

    /// "L03N" → "L03". Parent IDs are three characters; platforms add a direction letter.
    public static func parentID(of stopID: String) -> String {
        if stopID.count == 4, let last = stopID.last, last == "N" || last == "S" {
            return String(stopID.dropLast())
        }
        return stopID
    }
}

/// A station complex near the rider: every stop sharing a transfer complex, plus how far away it is.
public struct NearbyStation: Sendable, Equatable, Identifiable {
    public var id: String { complexID }
    public var complexID: String
    public var name: String
    public var stops: [Stop]
    public var distance: Double

    /// Rough walking time: straight-line distance stretched for the street grid, at ~80 m/min.
    public var walkingMinutes: Int {
        max(1, Int((distance * 1.3 / 80).rounded(.up)))
    }
}

public struct StationDirectory: Sendable {
    public enum Error: Swift.Error, Equatable {
        case missingColumn(String)
    }

    public let stops: [Stop]
    private let stopsByID: [String: Stop]

    public init(stops: [Stop]) {
        self.stops = stops
        self.stopsByID = Dictionary(stops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Parses the MTA "Subway Stations" export (data.ny.gov dataset 39hk-dx4f).
    public init(csv: String) throws {
        var rows = CSV.parse(csv)
        guard !rows.isEmpty else { throw Error.missingColumn("GTFS Stop ID") }
        let header = rows.removeFirst()

        func column(_ name: String) throws -> Int {
            guard let index = header.firstIndex(of: name) else { throw Error.missingColumn(name) }
            return index
        }
        let id = try column("GTFS Stop ID")
        let complex = try column("Complex ID")
        let name = try column("Stop Name")
        let routes = try column("Daytime Routes")
        let latitude = try column("GTFS Latitude")
        let longitude = try column("GTFS Longitude")
        let width = [id, complex, name, routes, latitude, longitude].max()!

        let stops = rows.compactMap { row -> Stop? in
            guard row.count > width,
                  let lat = Double(row[latitude]), let lon = Double(row[longitude])
            else { return nil }
            return Stop(
                id: row[id],
                complexID: row[complex],
                name: row[name],
                routes: row[routes].split(separator: " ").map(String.init),
                coordinate: Coordinate(latitude: lat, longitude: lon)
            )
        }
        self.init(stops: stops)
    }

    /// Looks up a stop by parent or platform ID ("L03" or "L03N").
    public func stop(id: String) -> Stop? {
        stopsByID[Stop.parentID(of: id)]
    }

    /// The closest station complexes, nearest first, measured to each complex's closest stop.
    public func nearestStations(to location: Coordinate, limit: Int, within maxDistance: Double = .infinity) -> [NearbyStation] {
        let byComplex = Dictionary(grouping: stops, by: \.complexID)
        let stations = byComplex.map { complexID, stops -> NearbyStation in
            let distances = stops.map { $0.coordinate.distance(to: location) }
            let nearest = stops[distances.indices.min { distances[$0] < distances[$1] }!]
            return NearbyStation(
                complexID: complexID,
                name: Self.displayName(for: stops, nearest: nearest),
                stops: stops,
                distance: distances.min()!
            )
        }
        return stations
            .filter { $0.distance <= maxDistance }
            .sorted { ($0.distance, $0.complexID) < ($1.distance, $1.complexID) }
            .prefix(limit)
            .map { $0 }
    }

    /// Complexes can mix names ("Times Sq-42 St" + "42 St-Port Authority Bus Terminal");
    /// use the name most of their stops share, falling back to the stop nearest the rider.
    private static func displayName(for stops: [Stop], nearest: Stop) -> String {
        let counts = Dictionary(stops.map { ($0.name, 1) }, uniquingKeysWith: +)
        let best = counts.values.max() ?? 0
        let leaders = counts.filter { $0.value == best }.map(\.key)
        return leaders.count == 1 ? leaders[0] : nearest.name
    }
}
