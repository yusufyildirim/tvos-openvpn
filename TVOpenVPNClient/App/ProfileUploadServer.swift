import Foundation
import Darwin
import Network

@MainActor
final class ProfileUploadServer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var displayURL = "http://:8080"
    @Published var lastMessage: String?

    private var listener: NWListener?
    private let port: NWEndpoint.Port = 8080
    private let onProfile: (String, Data) throws -> Void

    init(onProfile: @escaping (String, Data) throws -> Void) {
        self.onProfile = onProfile
        self.displayURL = "http://\(Self.localAddress() ?? "apple-tv.local"):\(port.rawValue)"
    }

    func start() {
        guard listener == nil else { return }

        do {
            let listener = try NWListener(using: .tcp, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.lastMessage = "Ready for uploads"
                    case .failed(let error):
                        self?.isRunning = false
                        self?.lastMessage = error.localizedDescription
                        self?.listener = nil
                    case .cancelled:
                        self?.isRunning = false
                        self?.listener = nil
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
        } catch {
            lastMessage = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private nonisolated func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                self.receive(on: connection, buffer: Data())
            }
        }
        connection.start(queue: .global(qos: .userInitiated))
    }

    private nonisolated func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }

            if let request = HTTPUploadRequest(data: nextBuffer) {
                Task { @MainActor in
                    do {
                        try self.onProfile(request.fileName, request.body)
                        self.lastMessage = "Imported \(request.fileName)"
                        self.respond("HTTP/1.1 201 Created\r\nConnection: close\r\n\r\nImported\n", on: connection)
                    } catch {
                        self.lastMessage = error.localizedDescription
                        self.respond("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n\(error.localizedDescription)\n", on: connection)
                    }
                }
                return
            }

            if isComplete || error != nil {
                Task { @MainActor in
                    self.respond("HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\nInvalid upload\n", on: connection)
                }
                return
            }

            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private nonisolated func respond(_ response: String, on connection: NWConnection) {
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func localAddress() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let address = interface.ifa_addr else { continue }
            guard address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name.hasPrefix("en") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            if result == 0 {
                let end = host.firstIndex(of: 0) ?? host.endIndex
                return String(decoding: host[..<end].map { UInt8(bitPattern: $0) }, as: UTF8.self)
            }
        }

        return nil
    }
}

private struct HTTPUploadRequest {
    let fileName: String
    let body: Data

    init?(data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let bodyStart = headerEnd.upperBound

        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2, requestParts[0] == "POST" else { return nil }

        let path = String(requestParts[1])
        let fileName = URL(string: path)?.lastPathComponent ?? "profile.ovpn"
        let contentLength = lines
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].caseInsensitiveCompare("Content-Length") == .orderedSame else {
                    return nil
                }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .first

        guard let contentLength else { return nil }
        let available = data.distance(from: bodyStart, to: data.endIndex)
        guard available >= contentLength else { return nil }

        let bodyEnd = data.index(bodyStart, offsetBy: contentLength)
        self.body = Data(data[bodyStart..<bodyEnd])
        self.fileName = SharedContainer.sanitizedProfileFileName(fileName)
    }
}
