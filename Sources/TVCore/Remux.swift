import Foundation
import Network

/// Plays files AVPlayer can't open: MKV and WebM, AVI, FLV, WMV/ASF, RMVB, MPEG program streams. They are
/// repackaged as HLS that AVPlayer plays like any other stream, so the picture keeps hardware decoding,
/// AirPlay audio, picture in picture and the player's own controls. See `RemuxSession`.
public enum Remux {
    /// Whether a file starting with these bytes is one the repackager opens and AVPlayer doesn't.
    public static func handles(_ head: Data) -> Bool {
        let bytes = [UInt8](head.prefix(16))
        guard bytes.count >= 4 else { return false }
        func text(_ range: Range<Int>) -> String { String(decoding: bytes[range], as: UTF8.self) }
        if bytes[0..<4].elementsEqual([0x1A, 0x45, 0xDF, 0xA3]) { return true }                       // Matroska, WebM
        if bytes.count >= 12, text(0..<4) == "RIFF", text(8..<12) == "AVI " { return true }
        if text(0..<3) == "FLV" { return true }
        if bytes[0..<4].elementsEqual([0x30, 0x26, 0xB2, 0x75]) { return true }                       // ASF (WMV)
        if text(0..<4) == ".RMF" { return true }                                                      // RealMedia
        if bytes[0..<4].elementsEqual([0x00, 0x00, 0x01, 0xBA]) { return true }                       // MPEG program stream
        return false
    }

    /// Whether a link names such a file, for addresses whose bytes aren't read before playing.
    public static func handles(name: String) -> Bool {
        ["mkv", "webm", "avi", "flv", "f4v", "wmv", "asf", "rm", "rmvb", "mpg", "mpeg", "vob", "divx", "xvid"]
            .contains((name as NSString).pathExtension.lowercased())
    }

    /// Opens the file and returns the address of its HLS master playlist on a loopback server.
    public static func open(_ source: RemuxSource) async throws -> URL {
        let session = RemuxSession(source: source)
        try await session.open()
        RemuxStore.shared.add(session)
        do {
            let base = try await RemuxServer.shared.base()
            return base.appending(path: "\(session.id)/master.m3u8")
        } catch {
            RemuxStore.shared.remove(session.id)?.close()
            throw error
        }
    }

    public static func isRemuxed(_ url: URL) -> Bool { session(url) != nil }

    /// Stops reading and writing the file behind `url`.
    public static func stop(_ url: URL) {
        guard let id = identifier(url) else { return }
        RemuxStore.shared.remove(id)?.close()
    }

    public static func transfer(for url: URL) -> (received: Int64, host: String?)? { session(url)?.source.transfer }

    /// A file behind an HTTP(S) link that answers byte ranges; read like a cloud drive's file.
    public static func httpSource(_ url: URL, headers: [String: String]) async throws -> RemuxSource {
        var request = URLRequest(url: url)
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let (_, response) = try await CloudByteStream.session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 206, let range = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Range"),
              let total = range.split(separator: "/").last.flatMap({ Int($0) }), total > 0 else {
            throw status >= 400 ? TVError.http(status) : TVError.unsupported("no byte ranges")
        }
        let source = CloudStreams.Source(url: url, headers: headers, length: total, name: url.lastPathComponent)
        return CloudRemuxSource(stream: CloudByteStream(source: source, rewritesSampleEntries: false, refresh: { nil }))
    }

    /// A file on this device.
    public static func fileSource(_ url: URL) throws -> RemuxSource { try FileRemuxSource(url) }

    private static func identifier(_ url: URL) -> String? {
        guard ["127.0.0.1", "localhost"].contains(url.host() ?? "") else { return nil }
        let parts = url.path().split(separator: "/")
        return parts.count == 3 ? String(parts[1]) : nil
    }
    private static func session(_ url: URL) -> RemuxSession? { identifier(url).flatMap(RemuxStore.shared.session) }
}

struct CloudRemuxSource: RemuxSource {
    let stream: CloudByteStream
    let length: Int64
    init(stream: CloudByteStream) {
        self.stream = stream
        length = Int64(stream.sourceLength)
    }
    func read(at offset: Int64, count: Int) async throws -> Data { try await stream.read(at: Int(offset), count: count) }
    var transfer: (received: Int64, host: String?)? { (stream.counter.value, stream.host) }
    func close() async { await stream.clear() }
}

final class FileRemuxSource: RemuxSource, @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    let length: Int64
    init(_ url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        length = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
    }
    func read(at offset: Int64, count: Int) async throws -> Data {
        try lock.withLock {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: count) ?? Data()
        }
    }
    var transfer: (received: Int64, host: String?)? { nil }
    func close() async { lock.withLock { try? handle.close() } }
}

/// The open files; the oldest is closed when a fourth opens (an episode queued behind another holds two).
final class RemuxStore: @unchecked Sendable {
    static let shared = RemuxStore()
    private let lock = NSLock()
    private var sessions: [String: RemuxSession] = [:]
    private var order: [String] = []

    func add(_ session: RemuxSession) {
        let retired: [RemuxSession] = lock.withLock {
            sessions[session.id] = session; order.append(session.id)
            var old: [RemuxSession] = []
            while order.count > 3 { if let value = sessions.removeValue(forKey: order.removeFirst()) { old.append(value) } }
            return old
        }
        retired.forEach { $0.close() }
    }
    func session(_ id: String) -> RemuxSession? { lock.withLock { sessions[id] } }
    func remove(_ id: String) -> RemuxSession? {
        lock.withLock {
            order.removeAll { $0 == id }
            return sessions.removeValue(forKey: id)
        }
    }
}

/// Serves the repackaged files to AVPlayer over loopback, behind a per-launch token. A segment is sent while
/// it is being written (chunked), so playback starts once its first second is ready.
actor RemuxServer {
    static let shared = RemuxServer()
    private let token = UUID().uuidString.lowercased()
    private let queue = DispatchQueue(label: "tvbox.remux.server")
    private var listener: NWListener?
    private var address: URL?
    private var starting: Task<URL, Error>?

    func base() async throws -> URL {
        // A suspended iOS app loses its sockets; a listener that is no longer ready is replaced.
        if let address, listener?.state == .ready { return address }
        if let starting { return try await starting.value }
        listener?.cancel(); listener = nil; address = nil
        let task = Task { try await self.listen() }
        starting = task
        defer { starting = nil }
        let value = try await task.value
        address = value
        return value
    }

    private func listen() async throws -> URL {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let server = try NWListener(using: parameters)
        listener = server
        let token = token
        server.newConnectionHandler = { connection in
            connection.start(queue: .global(qos: .userInitiated))
            Self.receive(connection, buffer: Data(), token: token)
        }
        let ready = OneShot<URL>()
        return try await withCheckedThrowingContinuation { continuation in
            ready.set(continuation)
            server.stateUpdateHandler = { [token] state in
                switch state {
                case .ready:
                    guard let port = server.port else { return }
                    ready.resume(.success(URL(string: "http://127.0.0.1:\(port.rawValue)/\(token)/")!))
                case .failed(let error): ready.resume(.failure(error))
                case .cancelled: ready.resume(.failure(CancellationError()))
                default: break
                }
            }
            server.start(queue: queue)
        }
    }

    private nonisolated static func receive(_ connection: NWConnection, buffer: Data, token: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { data, _, complete, error in
            var bytes = buffer
            if let data { bytes.append(data) }
            if bytes.range(of: Data("\r\n\r\n".utf8)) != nil { serve(connection, request: bytes, token: token) }
            else if error != nil || complete || bytes.count > 16384 { connection.cancel() }
            else { receive(connection, buffer: bytes, token: token) }
        }
    }

    private nonisolated static func serve(_ connection: NWConnection, request: Data, token: String) {
        let lines = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")
        let fields = (lines.first ?? "").split(separator: " ")
        guard fields.count >= 2, fields[0] == "GET" || fields[0] == "HEAD" else { return send(connection, status: 405) }
        let head = fields[0] == "HEAD"
        let parts = String(fields[1]).components(separatedBy: "?")[0].split(separator: "/").map(String.init)
        guard parts.count == 3, parts[0] == token, let session = RemuxStore.shared.session(parts[1]) else { return send(connection, status: 404) }
        let file = parts[2], name = (file as NSString).deletingPathExtension
        switch (file as NSString).pathExtension {
        case "m3u8":
            let text = name == "master" ? session.master : Int(name).flatMap { session.playlists[$0] }
            guard let text else { return send(connection, status: 404) }
            send(connection, status: 200, body: head ? Data() : Data(text.utf8), length: text.utf8.count, mime: "application/vnd.apple.mpegurl")
        case "mp4":
            guard let data = Int(name).flatMap({ session.initializations[$0] }) else { return send(connection, status: 404) }
            send(connection, status: 200, body: head ? Data() : data, length: data.count, mime: "video/mp4")
        case "m4s", "vtt":
            let numbers = name.split(separator: "-").compactMap { Int($0) }
            guard numbers.count == 2 else { return send(connection, status: 404) }
            if head { return send(connection, status: 200, mime: file.hasSuffix("vtt") ? "text/vtt" : "video/mp4") }
            guard let segment = session.segment(track: numbers[0], index: numbers[1]) else { return send(connection, status: 404) }
            stream(segment, of: session, to: connection, mime: file.hasSuffix("vtt") ? "text/vtt" : "video/mp4")
        default:
            send(connection, status: 404)
        }
    }

    private nonisolated static func stream(_ segment: RemuxSegment, of session: RemuxSession, to connection: NWConnection, mime: String) {
        let closed = ClosedFlag()
        // AVPlayer cancels a request by closing its connection: one more receive learns of it.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, complete, error in
            if complete || error != nil { closed.set(); segment.poke() }
        }
        connection.stateUpdateHandler = { state in
            switch state {
            case .failed, .cancelled: closed.set(); segment.poke()
            default: break
            }
        }
        Task {
            defer { session.leave(segment); connection.cancel() }
            var offset = 0, started = false
            do {
                while let bytes = try await segment.next(after: offset, cancelled: { closed.value }) {
                    if !started {
                        started = true
                        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nTransfer-Encoding: chunked\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
                        try await write(Data(header.utf8), to: connection)
                    }
                    offset += bytes.count
                    try await write(Data(String(bytes.count, radix: 16).utf8) + Data("\r\n".utf8) + bytes + Data("\r\n".utf8), to: connection)
                }
                if !started {
                    // An empty segment (a subtitle one without cues has its header at least).
                    try await write(Data("HTTP/1.1 200 OK\r\nContent-Type: \(mime)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), to: connection)
                } else {
                    try await write(Data("0\r\n\r\n".utf8), to: connection)
                }
            } catch {
                if !started, !closed.value {
                    try? await write(Data("HTTP/1.1 500 Internal Server Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8), to: connection)
                }
            }
        }
    }

    private nonisolated static func write(_ data: Data, to connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            })
        }
    }

    private nonisolated static func send(_ connection: NWConnection, status: Int, body: Data = Data(), length: Int? = nil, mime: String = "text/plain") {
        let reason = [200: "OK", 404: "Not Found", 405: "Method Not Allowed"][status] ?? "Error"
        let header = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(mime)\r\nContent-Length: \(length ?? body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}

private final class ClosedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false
    var value: Bool { lock.withLock { closed } }
    func set() { lock.withLock { closed = true } }
}
