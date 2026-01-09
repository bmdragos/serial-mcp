import Foundation

// MARK: - JSON-RPC Request

struct JSONRPCRequest: Codable, Sendable {
    let jsonrpc: String
    let id: RequestID?
    let method: String
    let params: JSONValue?

    enum RequestID: Codable, Equatable, Sendable {
        case string(String)
        case int(Int)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let intValue = try? container.decode(Int.self) {
                self = .int(intValue)
            } else if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else {
                throw DecodingError.typeMismatch(
                    RequestID.self,
                    DecodingError.Context(
                        codingPath: decoder.codingPath,
                        debugDescription: "Expected String or Int"
                    )
                )
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let s): try container.encode(s)
            case .int(let i): try container.encode(i)
            }
        }
    }
}

// MARK: - JSON-RPC Response

struct JSONRPCResponse: Codable, Sendable {
    let jsonrpc: String
    let id: JSONRPCRequest.RequestID?
    let result: JSONValue?
    let error: JSONRPCError?

    init(id: JSONRPCRequest.RequestID?, result: JSONValue) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = nil
    }

    init(id: JSONRPCRequest.RequestID?, error: JSONRPCError) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = nil
        self.error = error
    }
}

// MARK: - JSON-RPC Error

struct JSONRPCError: Codable, Sendable {
    let code: Int
    let message: String
    let data: JSONValue?

    init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    // Standard JSON-RPC error codes
    static func parseError(_ detail: String? = nil) -> JSONRPCError {
        JSONRPCError(code: -32700, message: "Parse error\(detail.map { ": \($0)" } ?? "")")
    }

    static func invalidRequest(_ detail: String? = nil) -> JSONRPCError {
        JSONRPCError(code: -32600, message: "Invalid Request\(detail.map { ": \($0)" } ?? "")")
    }

    static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)")
    }

    static func invalidParams(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: msg)
    }

    static func internalError(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32603, message: msg)
    }

    // MCP-specific error codes (-32000 to -32099)
    static func toolError(_ msg: String) -> JSONRPCError {
        JSONRPCError(code: -32000, message: msg)
    }
}
