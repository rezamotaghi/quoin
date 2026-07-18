import Foundation

/// Amendment 1: the wire vocabulary between the running app's agent endpoint
/// (a local unix socket speaking one JSON object per line) and its clients
/// (the QuoinMCP shim, or anything else on this machine). Pure Codable
/// data here so both sides share one definition and tests cover round-trips.

/// A minimal JSON value: what results are made of.
public indirect enum AgentJSON: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([AgentJSON])
    case object([String: AgentJSON])

    public init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null }
        else if let v = try? single.decode(Bool.self) { self = .bool(v) }
        else if let v = try? single.decode(Int.self) { self = .int(v) }
        else if let v = try? single.decode(Double.self) { self = .double(v) }
        else if let v = try? single.decode(String.self) { self = .string(v) }
        else if let v = try? single.decode([AgentJSON].self) { self = .array(v) }
        else if let v = try? single.decode([String: AgentJSON].self) { self = .object(v) }
        else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "not a JSON value"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .null: try single.encodeNil()
        case .bool(let v): try single.encode(v)
        case .int(let v): try single.encode(v)
        case .double(let v): try single.encode(v)
        case .string(let v): try single.encode(v)
        case .array(let v): try single.encode(v)
        case .object(let v): try single.encode(v)
        }
    }

    public var stringValue: String? { if case .string(let v) = self { v } else { nil } }
    public var intValue: Int? {
        switch self {
        case .int(let v): v
        case .double(let v): Int(v)
        case .string(let v): Int(v)
        default: nil
        }
    }
}

public struct AgentRequest: Codable, Sendable {
    public var id: Int
    public var method: String
    public var params: [String: AgentJSON]?

    public init(id: Int, method: String, params: [String: AgentJSON]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct AgentResponse: Codable, Sendable {
    public var id: Int
    public var result: AgentJSON?
    public var error: String?

    public init(id: Int, result: AgentJSON? = nil, error: String? = nil) {
        self.id = id
        self.result = result
        self.error = error
    }
}

public enum AgentWire {
    /// One request/response per line: encode compactly, no raw newlines.
    public static func encodeLine(_ value: some Encodable) -> Data? {
        guard var data = try? JSONEncoder().encode(value) else { return nil }
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, from line: Data) -> T? {
        try? JSONDecoder().decode(type, from: line)
    }
}
