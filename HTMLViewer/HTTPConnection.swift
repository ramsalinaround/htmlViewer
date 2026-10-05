import Foundation
import Network

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    /// The request body, streamed to a temporary file. Removed after the response.
    let bodyURL: URL?
}

struct HTTPResponse {
    enum Body {
        case data(Data)
        case file(URL, removeWhenDone: Bool)
    }

    var status: Int
    var headers: [String: String] = [:]
    var body: Body = .data(Data())

    static func json(_ object: Any, status: Int = 200) -> HTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: ["Content-Type": "application/json; charset=utf-8"], body: .data(data))
    }

    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        json(["error": message], status: status)
    }

    static func html(_ text: String) -> HTTPResponse {
        HTTPResponse(status: 200, headers: ["Content-Type": "text/html; charset=utf-8"], body: .data(Data(text.utf8)))
    }

    static func reason(for status: Int) -> String {
        switch status {
        case 100: "Continue"
        case 200: "OK"
        case 400: "Bad Request"
        case 403: "Forbidden"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 411: "Length Required"
        case 431: "Request Header Fields Too Large"
        case 503: "Service Unavailable"
        case 507: "Insufficient Storage"
        default: status < 400 ? "OK" : "Internal Server Error"
        }
    }
}

/// One HTTP/1.1 exchange: reads a request (streaming its body to disk so large
/// uploads don't sit in memory), answers it, and closes the connection.
final class HTTPConnection {
    private let connection: NWConnection
    private let handler: (HTTPRequest) -> HTTPResponse

    private var headerBuffer = Data()
    private var head: (method: String, target: String, headers: [String: String])?
    private var bodyURL: URL?
    private var bodyHandle: FileHandle?
    private var bodyRemaining = 0
    private var isResponding = false

    private static let maxHeaderSize = 64 * 1024
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    init(connection: NWConnection, handler: @escaping (HTTPRequest) -> HTTPResponse) {
        self.connection = connection
        self.handler = handler
    }

    func start(on queue: DispatchQueue) {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .failed, .cancelled:
                cleanUp()
                connection.stateUpdateHandler = nil
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 512 * 1024) { [self] data, _, isComplete, error in
            if let data, !data.isEmpty { consume(data) }
            guard !isResponding else { return }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            receive()
        }
    }

    private func consume(_ data: Data) {
        guard head == nil else {
            appendBody(data)
            return
        }

        headerBuffer.append(data)
        guard let end = headerBuffer.range(of: Self.headerTerminator) else {
            if headerBuffer.count > Self.maxHeaderSize { respond(.error(431, "Request headers too large.")) }
            return
        }
        guard let parsed = Self.parseHead(headerBuffer[headerBuffer.startIndex..<end.lowerBound]) else {
            respond(.error(400, "Malformed request."))
            return
        }
        head = parsed
        let rest = Data(headerBuffer[end.upperBound...])
        headerBuffer = Data()

        if parsed.headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            respond(.error(411, "Content-Length is required."))
            return
        }
        let length = Int(parsed.headers["content-length"] ?? "") ?? 0
        guard length > 0 else {
            dispatch()
            return
        }

        if parsed.headers["expect"]?.lowercased() == "100-continue" {
            connection.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .contentProcessed { _ in })
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "upload-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: url.path, contents: nil),
              let handle = try? FileHandle(forWritingTo: url) else {
            respond(.error(507, "Couldn't store the upload."))
            return
        }
        bodyURL = url
        bodyHandle = handle
        bodyRemaining = length
        if !rest.isEmpty { appendBody(rest) }
    }

    private func appendBody(_ data: Data) {
        guard bodyRemaining > 0, let bodyHandle else { return }
        let chunk = data.prefix(bodyRemaining)
        do {
            try bodyHandle.write(contentsOf: chunk)
        } catch {
            respond(.error(507, "Couldn't save the upload: \(error.localizedDescription)"))
            return
        }
        bodyRemaining -= chunk.count
        if bodyRemaining == 0 {
            try? bodyHandle.close()
            self.bodyHandle = nil
            dispatch()
        }
    }

    private func dispatch() {
        guard let head, let components = URLComponents(string: head.target) else {
            respond(.error(400, "Malformed request."))
            return
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        let request = HTTPRequest(
            method: head.method,
            path: components.path,
            query: query,
            headers: head.headers,
            bodyURL: bodyURL
        )
        respond(handler(request))
    }

    private func respond(_ response: HTTPResponse) {
        guard !isResponding else { return }
        isResponding = true

        var response = response
        var fileHandle: FileHandle?
        var contentLength = 0
        switch response.body {
        case .data(let data):
            contentLength = data.count
        case .file(let url, _):
            fileHandle = try? FileHandle(forReadingFrom: url)
            contentLength = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if fileHandle == nil {
                response = .error(404, "File not found.")
                if case .data(let data) = response.body { contentLength = data.count }
            }
        }

        var headers = response.headers
        headers["Content-Length"] = String(contentLength)
        headers["Connection"] = "close"
        headers["Cache-Control"] = headers["Cache-Control"] ?? "no-store"
        var text = "HTTP/1.1 \(response.status) \(HTTPResponse.reason(for: response.status))\r\n"
        for (name, value) in headers { text += "\(name): \(value)\r\n" }
        text += "\r\n"
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })

        switch response.body {
        case .data(let data):
            connection.send(content: data, isComplete: true, completion: .contentProcessed { [self] _ in
                connection.cancel()
            })
        case .file(let url, let removeWhenDone):
            if let fileHandle {
                sendFile(fileHandle, url: url, removeWhenDone: removeWhenDone)
            }
        }
    }

    /// Streams a file in 1 MB pieces, so large downloads don't sit in memory.
    private func sendFile(_ handle: FileHandle, url: URL, removeWhenDone: Bool) {
        let chunk = try? handle.read(upToCount: 1 << 20)
        guard let chunk, !chunk.isEmpty else {
            try? handle.close()
            if removeWhenDone { try? FileManager.default.removeItem(at: url) }
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { [self] _ in
                connection.cancel()
            })
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [self] error in
            if error != nil {
                try? handle.close()
                if removeWhenDone { try? FileManager.default.removeItem(at: url) }
                connection.cancel()
            } else {
                sendFile(handle, url: url, removeWhenDone: removeWhenDone)
            }
        })
    }

    private func cleanUp() {
        try? bodyHandle?.close()
        bodyHandle = nil
        if let bodyURL { try? FileManager.default.removeItem(at: bodyURL) }
        bodyURL = nil
    }

    private static func parseHead(_ data: Data) -> (method: String, target: String, headers: [String: String])? {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        var lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return (String(requestLine[0]).uppercased(), String(requestLine[1]), headers)
    }
}
