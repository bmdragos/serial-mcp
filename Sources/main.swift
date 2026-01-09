import Foundation

// Entry point - using direct async entry instead of @main to avoid issues
let server = MCPServer()

// Run the server
Task {
    await server.run()
}

// Keep the run loop alive
RunLoop.main.run()
