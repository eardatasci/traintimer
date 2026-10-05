/// How a route's bullet looks. Colors are the MTA's own (GTFS routes.txt route_color).
public struct RouteStyle: Sendable, Equatable {
    /// Text inside the bullet: "6", "S", "SIR".
    public var symbol: String
    /// Express variants (6X, 7X, FX) get a diamond instead of a circle.
    public var isExpress: Bool
    /// 0xRRGGBB
    public var color: UInt32
    /// Yellow N/Q/R/W bullets use black text.
    public var usesDarkText: Bool

    public init(routeID: String) {
        let isExpress = routeID.count == 2 && routeID.hasSuffix("X")
        let base = isExpress ? String(routeID.dropLast()) : routeID

        switch base {
        case "GS", "FS", "H": symbol = "S"
        case "SI": symbol = "SIR"
        default: symbol = base
        }
        self.isExpress = isExpress
        usesDarkText = ["N", "Q", "R", "W"].contains(base)

        switch base {
        case "1", "2", "3": color = 0xD82233
        case "4", "5", "6": color = 0x009952
        case "7": color = 0x9A38A1
        case "A", "C", "E": color = 0x0062CF
        case "B", "D", "F", "M": color = 0xEB6800
        case "G": color = 0x799534
        case "J", "Z": color = 0x8E5C33
        case "N", "Q", "R", "W": color = 0xF6BC26
        case "SI": color = 0x08179C
        default: color = 0x7C858C  // L, shuttles, anything new
        }
    }
}
