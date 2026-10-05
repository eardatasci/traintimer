import Foundation

/// Test-only protobuf encoder for building small GTFS-RT messages by hand.
struct ProtoWriter {
    private(set) var bytes: [UInt8] = []

    var data: Data { Data(bytes) }

    mutating func varint(_ field: Int, _ value: UInt64) {
        key(field, wireType: 0)
        appendVarint(value)
    }

    mutating func string(_ field: Int, _ value: String) {
        bytes(field, Array(value.utf8))
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        bytes(field, nested.bytes)
    }

    mutating func fixed32(_ field: Int, _ value: UInt32) {
        key(field, wireType: 5)
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    mutating func fixed64(_ field: Int, _ value: UInt64) {
        key(field, wireType: 1)
        withUnsafeBytes(of: value.littleEndian) { bytes.append(contentsOf: $0) }
    }

    private mutating func bytes(_ field: Int, _ payload: [UInt8]) {
        key(field, wireType: 2)
        appendVarint(UInt64(payload.count))
        bytes.append(contentsOf: payload)
    }

    private mutating func key(_ field: Int, wireType: UInt64) {
        appendVarint(UInt64(field) << 3 | wireType)
    }

    private mutating func appendVarint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            bytes.append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        bytes.append(UInt8(value))
    }
}
