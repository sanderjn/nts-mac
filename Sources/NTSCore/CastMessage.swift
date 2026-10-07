import Foundation

/// One message on a Cast v2 channel: a protobuf `CastMessage` carrying a JSON payload.
public struct CastMessage: Equatable, Sendable {
    public var source: String
    public var destination: String
    public var namespace: String
    public var payload: String

    public init(source: String = "sender-0", destination: String, namespace: String, payload: String) {
        self.source = source
        self.destination = destination
        self.namespace = namespace
        self.payload = payload
    }

    /// The protobuf body, without the length prefix.
    public func encoded() -> Data {
        var out = [UInt8]()
        out.appendVarint(field: 1, 0) // protocol_version: CASTV2_1_0
        out.appendString(field: 2, source)
        out.appendString(field: 3, destination)
        out.appendString(field: 4, namespace)
        out.appendVarint(field: 5, 0) // payload_type: STRING
        out.appendString(field: 6, payload)
        return Data(out)
    }

    /// The body prefixed with its length as a big-endian UInt32, as it goes over the socket.
    public func framed() -> Data {
        let body = encoded()
        return withUnsafeBytes(of: UInt32(body.count).bigEndian) { Data($0) } + body
    }

    public init?(decoding data: Data) {
        var reader = ProtoReader(bytes: [UInt8](data))
        var strings = [UInt64: String]()
        while !reader.isAtEnd {
            guard let tag = reader.varint() else { return nil }
            switch tag & 7 {
            case 0:
                guard reader.varint() != nil else { return nil }
            case 1:
                guard reader.take(8) != nil else { return nil }
            case 2:
                guard let length = reader.varint(), let bytes = reader.take(Int(clamping: length)) else { return nil }
                strings[tag >> 3] = String(decoding: bytes, as: UTF8.self)
            case 5:
                guard reader.take(4) != nil else { return nil }
            default:
                return nil
            }
        }
        guard let source = strings[2], let destination = strings[3], let namespace = strings[4] else { return nil }
        self.init(source: source, destination: destination, namespace: namespace, payload: strings[6] ?? "")
    }
}

private struct ProtoReader {
    let bytes: [UInt8]
    var offset = 0

    var isAtEnd: Bool { offset >= bytes.count }

    mutating func varint() -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while offset < bytes.count, shift < 64 {
            let byte = bytes[offset]
            offset += 1
            value |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }

    mutating func take(_ count: Int) -> ArraySlice<UInt8>? {
        guard count >= 0, count <= bytes.count - offset else { return nil }
        defer { offset += count }
        return bytes[offset..<offset + count]
    }
}

private extension [UInt8] {
    mutating func appendVarint(_ value: UInt64) {
        var value = value
        while value >= 0x80 {
            append(UInt8(value & 0x7F) | 0x80)
            value >>= 7
        }
        append(UInt8(value))
    }

    mutating func appendVarint(field: UInt64, _ value: UInt64) {
        appendVarint(field << 3)
        appendVarint(value)
    }

    mutating func appendString(field: UInt64, _ string: String) {
        let utf8 = Array(string.utf8)
        appendVarint(field << 3 | 2)
        appendVarint(UInt64(utf8.count))
        append(contentsOf: utf8)
    }
}
