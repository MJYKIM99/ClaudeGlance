//
//  IPCServer.swift
//  ClaudeGlance
//
//  Unix Socket + HTTP IPC 服务器 (带自动重连和端口冲突处理)
//

import Foundation
import Network
import Combine
import os

class IPCServer: ObservableObject {
    private var httpListener: NWListener?
    private var unixSocketHandle: FileHandle?
    private var unixSocketSource: DispatchSourceRead?
    private let socketPath = "/tmp/claude-glance.sock"

    // 端口配置：主端口和备用端口范围
    private let primaryPort: UInt16 = 19847
    private let portRange: ClosedRange<UInt16> = 19847...19857
    @Published var currentPort: UInt16 = 19847

    @Published var isRunning = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var statusMessage: String = ""

    private var reconnectTimer: Timer?
    private var serverFd: Int32 = -1

    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case error(String)

        var displayName: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var isHealthy: Bool {
            if case .connected = self { return true }
            return false
        }
    }

    var onMessage: ((Data) -> Void)?

    func start() throws {
        connectionStatus = .connecting
        statusMessage = "Starting server..."

        // 清理旧的 socket 文件
        try? FileManager.default.removeItem(atPath: socketPath)

        // 启动 Unix Socket 监听
        startUnixSocketServer()

        // 启动 HTTP 监听（带端口冲突重试）
        try startHTTPListenerWithRetry()

        isRunning = true
        connectionStatus = .connected
        statusMessage = "Server running on port \(currentPort)"
        AppLog.ipc.info("IPC Server started on port \(self.currentPort, privacy: .public)")

        // 启动健康检查定时器
        startHealthCheck()
    }

    func stop() {
        reconnectTimer?.invalidate()
        reconnectTimer = nil

        unixSocketSource?.cancel()
        unixSocketHandle?.closeFile()

        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }

        httpListener?.cancel()
        try? FileManager.default.removeItem(atPath: socketPath)

        isRunning = false
        connectionStatus = .disconnected
    }

    // MARK: - Health Check & Auto Reconnect
    private func startHealthCheck() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkAndReconnectIfNeeded()
        }
    }

    private func checkAndReconnectIfNeeded() {
        // 检查 socket 文件是否存在
        let socketExists = FileManager.default.fileExists(atPath: socketPath)

        // 检查服务器 fd 是否有效
        let fdValid = serverFd >= 0

        if !socketExists || !fdValid {
            AppLog.ipc.notice("Socket health check failed, attempting reconnect...")
            reconnect()
        }
    }

    private func reconnect() {
        connectionStatus = .connecting

        // 停止现有连接
        unixSocketSource?.cancel()
        if serverFd >= 0 {
            close(serverFd)
            serverFd = -1
        }

        // 清理旧的 socket 文件
        try? FileManager.default.removeItem(atPath: socketPath)

        // 延迟重连
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.startUnixSocketServer()

            if self?.serverFd ?? -1 >= 0 {
                self?.connectionStatus = .connected
                AppLog.ipc.info("Reconnected successfully")
            } else {
                self?.connectionStatus = .error("Failed to reconnect")
                AppLog.ipc.error("Reconnect failed")
            }
        }
    }

    // MARK: - Unix Socket (使用 POSIX API)
    private func startUnixSocketServer() {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            AppLog.ipc.error("Failed to create Unix socket")
            connectionStatus = .error("Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // 复制路径到 sun_path
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let pathPtr = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
            _ = socketPath.withCString { cstr in
                strcpy(pathPtr, cstr)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        // 绑定
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(fd, sockaddrPtr, addrLen)
            }
        }

        guard bindResult == 0 else {
            AppLog.ipc.error("Failed to bind Unix socket: \(errno)")
            connectionStatus = .error("Bind failed: \(errno)")
            close(fd)
            return
        }

        // 监听
        guard listen(fd, 5) == 0 else {
            AppLog.ipc.error("Failed to listen on Unix socket: \(errno)")
            connectionStatus = .error("Listen failed: \(errno)")
            close(fd)
            return
        }

        serverFd = fd
        AppLog.ipc.info("Unix socket listening at \(self.socketPath, privacy: .public)")

        // 使用 GCD 处理连接
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in
            self?.acceptUnixConnection(serverFd: fd)
        }
        source.setCancelHandler { [weak self] in
            if self?.serverFd == fd {
                close(fd)
                self?.serverFd = -1
            }
        }
        source.resume()
        unixSocketSource = source
    }

    private func acceptUnixConnection(serverFd: Int32) {
        var clientAddr = sockaddr_un()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                accept(serverFd, sockaddrPtr, &clientAddrLen)
            }
        }

        guard clientFd >= 0 else { return }

        // 读取数据
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 65536)
            let bytesRead = read(clientFd, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])
                DispatchQueue.main.async {
                    self?.onMessage?(data)
                }
            }

            close(clientFd)
        }
    }

    // MARK: - HTTP Server
    private func startHTTPListenerWithRetry() throws {
        var lastError: Error?

        for port in portRange {
            do {
                try startHTTPListener(on: port)
                currentPort = port
                if port != primaryPort {
                    AppLog.ipc.info("Using fallback port \(port, privacy: .public) (primary port \(self.primaryPort, privacy: .public) was unavailable)")
                    statusMessage = "Using port \(port) (fallback)"
                }
                return
            } catch {
                lastError = error
                AppLog.ipc.info("Port \(port) unavailable: \(error.localizedDescription)")
                continue
            }
        }

        // 所有端口都失败
        let errorMsg = "All ports \(portRange.lowerBound)-\(portRange.upperBound) unavailable"
        connectionStatus = .error(errorMsg)
        statusMessage = errorMsg
        throw lastError ?? NSError(domain: "IPCServer", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
    }

    private func startHTTPListener(on port: UInt16) throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)

        // 使用信号量等待监听器状态
        let semaphore = DispatchSemaphore(value: 0)
        var startError: Error?

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                AppLog.ipc.info("HTTP server listening on port \(port)")
                semaphore.signal()
            case .failed(let error):
                AppLog.ipc.error("HTTP listener failed on port \(port): \(error)")
                startError = error
                semaphore.signal()
            case .waiting(let error):
                AppLog.ipc.info("HTTP listener waiting on port \(port): \(error)")
                startError = error
                semaphore.signal()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.handleHTTPConnection(connection)
        }

        listener.start(queue: .global(qos: .userInitiated))

        // 等待最多 2 秒
        let result = semaphore.wait(timeout: .now() + 2)

        if result == .timedOut {
            listener.cancel()
            throw NSError(domain: "IPCServer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Listener start timeout"])
        }

        if let error = startError {
            listener.cancel()
            throw error
        }

        httpListener = listener
    }

    private func handleHTTPConnection(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            defer { connection.cancel() }

            guard let data = data, error == nil else { return }

            // 解析 HTTP 请求
            if let requestString = String(data: data, encoding: .utf8) {
                self?.parseHTTPRequest(requestString, connection: connection)
            }
        }
    }

    private func parseHTTPRequest(_ request: String, connection: NWConnection) {
        // 简单的 HTTP 解析
        let lines = request.components(separatedBy: "\r\n")

        guard let firstLine = lines.first,
              firstLine.hasPrefix("POST") else {
            sendHTTPResponse(connection, status: 405, body: "Method Not Allowed")
            return
        }

        // 找到 body (空行之后)
        if let bodyIndex = lines.firstIndex(of: "") {
            let bodyLines = lines[(bodyIndex + 1)...]
            let body = bodyLines.joined(separator: "\r\n")

            if let bodyData = body.data(using: .utf8), !bodyData.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    self?.onMessage?(bodyData)
                }
                sendHTTPResponse(connection, status: 200, body: "{\"status\":\"ok\"}")
            } else {
                sendHTTPResponse(connection, status: 400, body: "Empty body")
            }
        } else {
            sendHTTPResponse(connection, status: 400, body: "Invalid request")
        }
    }

    private func sendHTTPResponse(_ connection: NWConnection, status: Int, body: String) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 400: statusText = "Bad Request"
        case 405: statusText = "Method Not Allowed"
        default: statusText = "Unknown"
        }

        let response = """
        HTTP/1.1 \(status) \(statusText)\r
        Content-Type: application/json\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """

        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}
