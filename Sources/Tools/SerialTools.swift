import Foundation

// MARK: - Serial Open Tool

struct SerialOpenTool: Tool {
    let name = "arduino_serial_open"
    let description = "Open a serial connection to a device. Data is buffered for non-blocking reads."

    var inputSchema: [String: JSONValue] {
        Schema.object(properties: [
            "port": Schema.string(description: "Serial port (e.g., '/dev/cu.usbmodem14101')"),
            "baud": Schema.int(description: "Baud rate (default: 115200)")
        ], required: ["port"])
    }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> String {
        guard let port = arguments["port"]?.stringValue else {
            throw ToolError("Missing required argument: port")
        }

        let baud = arguments["baud"]?.intValue ?? 115200

        try await context.serialManager.open(port: port, baudRate: baud)

        return "✓ Serial port opened: \(port) at \(baud) baud"
    }
}

// MARK: - Serial Read Tool

struct SerialReadTool: Tool {
    let name = "arduino_serial_read"
    let description = "Read buffered serial output. Non-blocking - returns immediately with available data."

    var inputSchema: [String: JSONValue] {
        Schema.object(properties: [
            "port": Schema.string(description: "Serial port (uses first open port if omitted)"),
            "lines": Schema.int(description: "Number of recent lines to return (returns all buffered if omitted)"),
            "clear": Schema.bool(description: "Clear buffer after reading (default: true)")
        ])
    }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> String {
        // Get port - use specified or first open port
        let port: String
        if let specifiedPort = arguments["port"]?.stringValue {
            port = specifiedPort
        } else {
            let openPorts = await context.serialManager.openPorts()
            guard let firstPort = openPorts.first else {
                throw ToolError("No serial ports open. Use arduino_serial_open first.")
            }
            port = firstPort
        }

        let lines = arguments["lines"]?.intValue
        let data = try await context.serialManager.read(port: port, lines: lines)

        if data.isEmpty {
            return "(no data in buffer)"
        }

        return data.joined(separator: "\n")
    }
}

// MARK: - Serial Write Tool

struct SerialWriteTool: Tool {
    let name = "arduino_serial_write"
    let description = "Send text/command to a device over serial."

    var inputSchema: [String: JSONValue] {
        Schema.object(properties: [
            "text": Schema.string(description: "Text to send (newline appended automatically)"),
            "port": Schema.string(description: "Serial port (uses first open port if omitted)")
        ], required: ["text"])
    }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> String {
        guard let text = arguments["text"]?.stringValue else {
            throw ToolError("Missing required argument: text")
        }

        // Get port - use specified or first open port
        let port: String
        if let specifiedPort = arguments["port"]?.stringValue {
            port = specifiedPort
        } else {
            let openPorts = await context.serialManager.openPorts()
            guard let firstPort = openPorts.first else {
                throw ToolError("No serial ports open. Use arduino_serial_open first.")
            }
            port = firstPort
        }

        try await context.serialManager.write(port: port, text: text)

        return "✓ Sent: \(text)"
    }
}

// MARK: - Serial Close Tool

struct SerialCloseTool: Tool {
    let name = "arduino_serial_close"
    let description = "Close a serial connection."

    var inputSchema: [String: JSONValue] {
        Schema.object(properties: [
            "port": Schema.string(description: "Serial port to close (closes all if omitted)")
        ])
    }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> String {
        if let port = arguments["port"]?.stringValue {
            try await context.serialManager.close(port: port)
            return "✓ Closed: \(port)"
        } else {
            let ports = await context.serialManager.openPorts()
            await context.serialManager.closeAll()
            if ports.isEmpty {
                return "No ports were open"
            }
            return "✓ Closed \(ports.count) port(s): \(ports.joined(separator: ", "))"
        }
    }
}

// MARK: - Serial Status Tool

struct SerialStatusTool: Tool {
    let name = "arduino_serial_status"
    let description = "Check status of serial connections."

    var inputSchema: [String: JSONValue] {
        Schema.object(properties: [
            "port": Schema.string(description: "Specific port to check (shows all open ports if omitted)")
        ])
    }

    func execute(arguments: [String: JSONValue], context: ToolContext) async throws -> String {
        if let port = arguments["port"]?.stringValue {
            let status = await context.serialManager.status(port: port)
            if status.isOpen {
                return """
                Port: \(status.port)
                  Status: Open
                  Baud: \(status.baudRate)
                  Buffered Lines: \(status.bufferedLines)
                """
            } else {
                return "Port \(port) is not open"
            }
        } else {
            let ports = await context.serialManager.openPorts()
            if ports.isEmpty {
                return "No serial ports open"
            }

            var output = "Open Ports:\n"
            for port in ports {
                let status = await context.serialManager.status(port: port)
                output += "\n  \(port)\n"
                output += "    Baud: \(status.baudRate)\n"
                output += "    Buffered Lines: \(status.bufferedLines)\n"
            }
            return output
        }
    }
}
