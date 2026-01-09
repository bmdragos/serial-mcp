import Foundation

// MARK: - Serial Connection

/// Represents an active serial connection with buffered I/O
final class SerialConnection: @unchecked Sendable {
    let port: String
    let baudRate: Int
    let fileHandle: FileHandle
    private let readSource: DispatchSourceRead
    private let queue = DispatchQueue(label: "serial.read")
    private let lock = NSLock()

    private var _buffer: [String] = []
    private let maxBufferLines = 1000

    var buffer: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _buffer
    }

    var isOpen: Bool {
        !readSource.isCancelled
    }

    init(port: String, baudRate: Int, fileDescriptor: Int32) {
        self.port = port
        self.baudRate = baudRate
        self.fileHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)

        // Set up async read source
        self.readSource = DispatchSource.makeReadSource(
            fileDescriptor: fileDescriptor,
            queue: queue
        )

        readSource.setEventHandler { [weak self] in
            self?.handleRead()
        }

        readSource.setCancelHandler { [weak self] in
            self?.fileHandle.closeFile()
        }

        readSource.resume()
    }

    private func handleRead() {
        let data = fileHandle.availableData
        guard !data.isEmpty else { return }

        if let str = String(data: data, encoding: .utf8) {
            lock.lock()
            // Split into lines and append
            let lines = str.components(separatedBy: .newlines)
            for line in lines where !line.isEmpty {
                _buffer.append(line)
            }
            // Trim buffer if too large
            if _buffer.count > maxBufferLines {
                _buffer = Array(_buffer.suffix(maxBufferLines))
            }
            lock.unlock()
        }
    }

    func readLines(count: Int? = nil) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        if let count = count {
            let lines = Array(_buffer.suffix(count))
            return lines
        } else {
            let lines = _buffer
            _buffer = []
            return lines
        }
    }

    func write(_ text: String) throws {
        guard let data = (text + "\n").data(using: .utf8) else {
            throw SerialError.encodingError
        }
        try fileHandle.write(contentsOf: data)
    }

    func close() {
        readSource.cancel()
    }
}

// MARK: - Serial Error

enum SerialError: Error, LocalizedError {
    case portNotFound(String)
    case openFailed(String, Int32)
    case configurationFailed(String)
    case notOpen(String)
    case alreadyOpen(String)
    case encodingError
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .portNotFound(let port):
            return "Port not found: \(port)"
        case .openFailed(let port, let errno):
            return "Failed to open \(port): errno \(errno)"
        case .configurationFailed(let msg):
            return "Configuration failed: \(msg)"
        case .notOpen(let port):
            return "Port not open: \(port)"
        case .alreadyOpen(let port):
            return "Port already open: \(port)"
        case .encodingError:
            return "Failed to encode text as UTF-8"
        case .writeFailed(let msg):
            return "Write failed: \(msg)"
        }
    }
}

// MARK: - Serial Manager Actor

/// Actor managing serial port connections with async buffered I/O
actor SerialManager {
    private var connections: [String: SerialConnection] = [:]

    /// Open a serial port with specified baud rate
    func open(port: String, baudRate: Int) throws {
        guard connections[port] == nil else {
            throw SerialError.alreadyOpen(port)
        }

        // Open the port
        let fd = Darwin.open(port, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            throw SerialError.openFailed(port, errno)
        }

        // Configure termios
        var options = termios()
        tcgetattr(fd, &options)

        // Set baud rate
        let speed = baudRateToSpeed(baudRate)
        cfsetispeed(&options, speed)
        cfsetospeed(&options, speed)

        // 8N1 mode
        options.c_cflag &= ~tcflag_t(PARENB)  // No parity
        options.c_cflag &= ~tcflag_t(CSTOPB)  // 1 stop bit
        options.c_cflag &= ~tcflag_t(CSIZE)   // Clear size bits
        options.c_cflag |= tcflag_t(CS8)      // 8 data bits
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)  // Enable receiver, ignore modem control

        // Raw input
        options.c_lflag &= ~tcflag_t(ICANON | ECHO | ECHOE | ISIG)

        // Raw output
        options.c_oflag &= ~tcflag_t(OPOST)

        // No flow control
        options.c_iflag &= ~tcflag_t(IXON | IXOFF | IXANY)

        // Apply settings
        guard tcsetattr(fd, TCSANOW, &options) == 0 else {
            Darwin.close(fd)
            throw SerialError.configurationFailed("tcsetattr failed")
        }

        // Clear non-blocking for reads (DispatchSource handles async)
        var flags = fcntl(fd, F_GETFL)
        flags &= ~O_NONBLOCK
        _ = fcntl(fd, F_SETFL, flags)

        // Flush any pending data
        tcflush(fd, TCIOFLUSH)

        let connection = SerialConnection(port: port, baudRate: baudRate, fileDescriptor: fd)
        connections[port] = connection
    }

    /// Close a serial port
    func close(port: String) throws {
        guard let connection = connections.removeValue(forKey: port) else {
            throw SerialError.notOpen(port)
        }
        connection.close()
    }

    /// Close all open ports
    func closeAll() {
        for (_, connection) in connections {
            connection.close()
        }
        connections.removeAll()
    }

    /// Read buffered lines from a port
    func read(port: String, lines: Int? = nil) throws -> [String] {
        guard let connection = connections[port] else {
            throw SerialError.notOpen(port)
        }
        return connection.readLines(count: lines)
    }

    /// Write text to a port
    func write(port: String, text: String) throws {
        guard let connection = connections[port] else {
            throw SerialError.notOpen(port)
        }
        try connection.write(text)
    }

    /// Get status of a port
    func status(port: String) -> SerialStatus {
        if let connection = connections[port] {
            return SerialStatus(
                port: port,
                isOpen: connection.isOpen,
                baudRate: connection.baudRate,
                bufferedLines: connection.buffer.count
            )
        }
        return SerialStatus(port: port, isOpen: false, baudRate: 0, bufferedLines: 0)
    }

    /// Get all open ports
    func openPorts() -> [String] {
        Array(connections.keys)
    }

    // MARK: - Baud Rate Conversion

    private func baudRateToSpeed(_ baudRate: Int) -> speed_t {
        switch baudRate {
        case 300: return speed_t(B300)
        case 600: return speed_t(B600)
        case 1200: return speed_t(B1200)
        case 2400: return speed_t(B2400)
        case 4800: return speed_t(B4800)
        case 9600: return speed_t(B9600)
        case 19200: return speed_t(B19200)
        case 38400: return speed_t(B38400)
        case 57600: return speed_t(B57600)
        case 115200: return speed_t(B115200)
        case 230400: return speed_t(B230400)
        default: return speed_t(B115200)  // Default to 115200
        }
    }
}

// MARK: - Serial Status

struct SerialStatus: Sendable {
    let port: String
    let isOpen: Bool
    let baudRate: Int
    let bufferedLines: Int
}
