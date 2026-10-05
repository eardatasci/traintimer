import Foundation

/// Minimal protobuf wire-format reader: just enough to walk GTFS-Realtime messages
/// without generated code or a SwiftProtobuf dependency.
struct ProtoReader {
    enum Error: Swift.Error, Equatable {
        case truncated
        case malformedVarint
        case unsupportedWireType(Int)
    }

    enum WireType: Int {
        case varint = 0
        case fixed64 = 1
        case lengthDelimited = 2
        case fixed32 = 5
    }

    private let bytes: [UInt8]
    private var index: Int
    private let end: Int

    init(_ data: Data) {
        self.init(bytes: [UInt8](data), range: 0..<data.count)
    }

    private init(bytes: [UInt8], range: Range<Int>) {
        self.bytes = bytes
        self.index = range.lowerBound
        self.end = range.upperBound
    }

    var isAtEnd: Bool { index >= end }

    /// Reads the next field key. Returns nil at the end of the message.
    mutating func nextField() throws -> (number: Int, wireType: WireType)? {
        guard !isAtEnd else { return nil }
        let key = try readVarint()
        let rawWireType = Int(key & 0x7)
        guard let wireType = WireType(rawValue: rawWireType) else {
            throw Error.unsupportedWireType(rawWireType)
        }
        return (Int(key >> 3), wireType)
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < end else { throw Error.truncated }
            let byte = bytes[index]
            index += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
            if shift >= 64 { throw Error.malformedVarint }
        }
    }

    mutating func readString() throws -> String {
        let range = try readLengthDelimitedRange()
        return String(decoding: bytes[range], as: UTF8.self)
    }

    /// Returns a reader scoped to the embedded message at the current position.
    mutating func readMessage() throws -> ProtoReader {
        ProtoReader(bytes: bytes, range: try readLengthDelimitedRange())
    }

    mutating func skip(_ wireType: WireType) throws {
        switch wireType {
        case .varint: _ = try readVarint()
        case .fixed64: try advance(by: 8)
        case .fixed32: try advance(by: 4)
        case .lengthDelimited: _ = try readLengthDelimitedRange()
        }
    }

    private mutating func readLengthDelimitedRange() throws -> Range<Int> {
        let length = try readVarint()
        guard length <= UInt64(end - index) else { throw Error.truncated }
        let start = index
        index += Int(length)
        return start..<index
    }

    private mutating func advance(by count: Int) throws {
        guard count <= end - index else { throw Error.truncated }
        index += count
    }
}
