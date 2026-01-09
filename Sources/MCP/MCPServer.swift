import Foundation

// MARK: - MCP Server

actor MCPServer {
    static let name = "serial-mcp"
    static let version = "1.0.0"

    private let toolRegistry = ToolRegistry()
    private let serialManager = SerialManager()

    private var toolContext: ToolContext {
        ToolContext(serialManager: serialManager)
    }

    func run() async {
        // Disable buffering for immediate output
        setbuf(stdout, nil)
        setbuf(stderr, nil)

        // Register serial tools
        registerTools()

        // Log startup to stderr (not to stdout which is for MCP protocol)
        log("Serial MCP Server v\(Self.version) started")

        // Use async stream for non-blocking stdin reading
        let stdinStream = AsyncStream<String> { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                while let line = readLine() {
                    continuation.yield(line)
                }
                continuation.finish()
            }
        }

        // Process lines as they come in
        for await line in stdinStream {
            guard !line.isEmpty else { continue }
            await processLine(line)
        }

        // Cleanup
        await serialManager.closeAll()
        log("Server shutting down")
    }

    private func processLine(_ line: String) async {
        guard let data = line.data(using: .utf8) else { return }

        do {
            let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
            let response = await handleRequest(request)
            sendResponse(response)
        } catch {
            let errorResponse = JSONRPCResponse(
                id: nil,
                error: .parseError(error.localizedDescription)
            )
            sendResponse(errorResponse)
        }
    }

    private func handleRequest(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        switch request.method {
        case "initialize":
            return handleInitialize(request)

        case "notifications/initialized":
            return JSONRPCResponse(id: request.id, result: .object([:]))

        case "tools/list":
            return handleToolsList(request)

        case "tools/call":
            return await handleToolCall(request)

        case "ping":
            return JSONRPCResponse(id: request.id, result: .object([:]))

        default:
            return JSONRPCResponse(id: request.id, error: .methodNotFound(request.method))
        }
    }

    private func handleInitialize(_ request: JSONRPCRequest) -> JSONRPCResponse {
        JSONRPCResponse(id: request.id, result: .object([
            "protocolVersion": "2024-11-05",
            "capabilities": .object([
                "tools": .object([:])
            ]),
            "serverInfo": .object([
                "name": .string(Self.name),
                "version": .string(Self.version)
            ])
        ]))
    }

    private func handleToolsList(_ request: JSONRPCRequest) -> JSONRPCResponse {
        let tools = toolRegistry.listTools()
        return JSONRPCResponse(id: request.id, result: .object([
            "tools": .array(tools)
        ]))
    }

    private func handleToolCall(_ request: JSONRPCRequest) async -> JSONRPCResponse {
        guard let params = request.params?.objectValue,
              let name = params["name"]?.stringValue else {
            return JSONRPCResponse(
                id: request.id,
                error: .invalidParams("Missing tool name")
            )
        }

        let arguments = params["arguments"]?.objectValue ?? [:]

        do {
            let result = try await toolRegistry.callTool(
                name: name,
                arguments: arguments,
                context: toolContext
            )
            return JSONRPCResponse(id: request.id, result: .object([
                "content": .array([
                    .object([
                        "type": "text",
                        "text": .string(result)
                    ])
                ])
            ]))
        } catch let error as ToolError {
            return JSONRPCResponse(id: request.id, result: .object([
                "content": .array([
                    .object([
                        "type": "text",
                        "text": .string("Error: \(error.message)")
                    ])
                ]),
                "isError": .bool(true)
            ]))
        } catch {
            return JSONRPCResponse(id: request.id, result: .object([
                "content": .array([
                    .object([
                        "type": "text",
                        "text": .string("Error: \(error.localizedDescription)")
                    ])
                ]),
                "isError": .bool(true)
            ]))
        }
    }

    private func sendResponse(_ response: JSONRPCResponse) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        if let data = try? encoder.encode(response),
           let jsonString = String(data: data, encoding: .utf8) {
            print(jsonString)
            fflush(stdout)
        }
    }

    private func log(_ message: String) {
        fputs("[serial-mcp] \(message)\n", stderr)
    }

    // MARK: - Tool Registration

    private func registerTools() {
        // Serial Monitor - the only tools we need
        toolRegistry.register(SerialOpenTool())
        toolRegistry.register(SerialReadTool())
        toolRegistry.register(SerialWriteTool())
        toolRegistry.register(SerialCloseTool())
        toolRegistry.register(SerialStatusTool())
    }
}
