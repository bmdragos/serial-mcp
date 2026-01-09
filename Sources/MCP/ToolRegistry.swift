import Foundation

// MARK: - Tool Protocol

protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var inputSchema: [String: JSONValue] { get }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> String
}

// MARK: - Tool Context

/// Context passed to tools providing access to shared managers
struct ToolContext: Sendable {
    let serialManager: SerialManager
}

// MARK: - Tool Error

struct ToolError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

// MARK: - Tool Registry

final class ToolRegistry: @unchecked Sendable {
    private var tools: [String: Tool] = [:]
    private let lock = NSLock()

    func register(_ tool: Tool) {
        lock.lock()
        defer { lock.unlock() }
        tools[tool.name] = tool
    }

    func listTools() -> [JSONValue] {
        lock.lock()
        defer { lock.unlock() }
        return tools.values.map { tool in
            .object([
                "name": .string(tool.name),
                "description": .string(tool.description),
                "inputSchema": .object(tool.inputSchema)
            ])
        }
    }

    func callTool(name: String, arguments: [String: JSONValue], context: ToolContext) async throws -> String {
        let tool: Tool? = {
            lock.lock()
            defer { lock.unlock() }
            return tools[name]
        }()

        guard let tool else {
            throw ToolError("Unknown tool: \(name)")
        }

        return try await tool.execute(arguments: arguments, context: context)
    }
}

// MARK: - Input Schema Helpers

/// Helpers for building JSON Schema for tool inputs
enum Schema {
    static func object(
        properties: [String: JSONValue],
        required: [String] = []
    ) -> [String: JSONValue] {
        var schema: [String: JSONValue] = [
            "type": "object",
            "properties": .object(properties)
        ]
        if !required.isEmpty {
            schema["required"] = .array(required.map { .string($0) })
        }
        return schema
    }

    static func string(description: String) -> JSONValue {
        .object([
            "type": "string",
            "description": .string(description)
        ])
    }

    static func int(description: String) -> JSONValue {
        .object([
            "type": "integer",
            "description": .string(description)
        ])
    }

    static func number(description: String) -> JSONValue {
        .object([
            "type": "number",
            "description": .string(description)
        ])
    }

    static func bool(description: String) -> JSONValue {
        .object([
            "type": "boolean",
            "description": .string(description)
        ])
    }

    static func array(description: String, items: JSONValue) -> JSONValue {
        .object([
            "type": "array",
            "description": .string(description),
            "items": items
        ])
    }

    static func `enum`(description: String, values: [String]) -> JSONValue {
        .object([
            "type": "string",
            "description": .string(description),
            "enum": .array(values.map { .string($0) })
        ])
    }
}
