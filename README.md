<p align="center">
  <img src="logo.png" alt="serial-mcp logo" width="400">
</p>

# serial-mcp

A minimal MCP server for non-blocking serial communication. Built for [Claude Code](https://claude.ai/code) to interact with Arduino, ESP32, and other serial devices without hanging.

## Why?

Serial monitors like `screen` and `arduino-cli monitor` block the terminal and hang Claude Code indefinitely. This MCP provides:

- **Non-blocking reads** - Data buffers in the background, read when you need it
- **Persistent connections** - Keep ports open across multiple tool calls
- **Real-time debugging** - Send commands, read responses, without switching terminals

## Tools

| Tool | Description |
|------|-------------|
| `arduino_serial_open` | Open a serial port and start buffering data |
| `arduino_serial_read` | Read buffered data (non-blocking, returns immediately) |
| `arduino_serial_write` | Send text/command to the device |
| `arduino_serial_close` | Close the connection |
| `arduino_serial_status` | Check open ports and buffer sizes |

## Installation

### Via Mint (recommended)

```bash
brew install mint
mint install bmdragos/serial-mcp
```

### Build from source

```bash
git clone https://github.com/bmdragos/serial-mcp.git
cd serial-mcp
swift build -c release
```

The binary will be at `.build/release/serial-mcp`

### Configure Claude Code

Add to your `~/.claude.json`:

```json
{
  "mcpServers": {
    "serial": {
      "type": "stdio",
      "command": "~/.mint/bin/serial-mcp"
    }
  }
}
```

If you built from source, use the full path to `.build/release/serial-mcp` instead.

## Usage

```
# Open a serial port
arduino_serial_open /dev/cu.usbmodem14101 115200

# Send a command
arduino_serial_write "help"

# Read the response (non-blocking)
arduino_serial_read

# Check connection status
arduino_serial_status

# Close when done
arduino_serial_close
```

## Requirements

- macOS 13+
- Swift 5.9+

## License

MIT
