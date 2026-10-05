import Foundation
import Network
import UniformTypeIdentifiers

/// A small web server for moving files between a computer's browser and the
/// app's folder over Wi-Fi. Runs only while the Wi-Fi Transfer screen is open.
final class TransferServer {
    enum State: Equatable {
        case starting
        case running(port: UInt16)
        case failed(String)
    }

    private let root: URL
    private let onState: @MainActor (State) -> Void
    private let onFilesChanged: @MainActor () -> Void
    private let queue = DispatchQueue(label: "HTMLViewer.TransferServer")
    private var listener: NWListener?

    init(root: URL, onState: @escaping @MainActor (State) -> Void, onFilesChanged: @escaping @MainActor () -> Void) {
        self.root = root
        self.onState = onState
        self.onFilesChanged = onFilesChanged
    }

    func start() {
        queue.async { [self] in startListener(port: 8080) }
    }

    func stop() {
        queue.async { [self] in
            listener?.cancel()
            listener = nil
        }
    }

    /// Tries a memorable port first, then lets the system pick one.
    private func startListener(port: UInt16?) {
        report(.starting)
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        do {
            if let port, let endpointPort = NWEndpoint.Port(rawValue: port) {
                listener = try NWListener(using: parameters, on: endpointPort)
            } else {
                listener = try NWListener(using: parameters)
            }
        } catch {
            report(.failed(error.localizedDescription))
            return
        }

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self, let listener, listener === self.listener else { return }
            switch state {
            case .ready:
                report(.running(port: listener.port?.rawValue ?? 0))
            case .failed(let error):
                listener.cancel()
                self.listener = nil
                if port != nil, case .posix(.EADDRINUSE) = error {
                    startListener(port: nil)
                } else {
                    report(.failed(error.localizedDescription))
                }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            HTTPConnection(connection: connection) { [weak self] request in
                self?.handle(request) ?? .error(503, "The server stopped.")
            }
            .start(on: queue)
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func report(_ state: State) {
        Task { @MainActor [onState] in onState(state) }
    }

    private func filesChanged() {
        Task { @MainActor [onFilesChanged] in onFilesChanged() }
    }

    // MARK: - Routes

    private func handle(_ request: HTTPRequest) -> HTTPResponse {
        let path = request.query["path"] ?? ""
        switch (request.method, request.path) {
        case ("GET", "/"), ("GET", "/index.html"):
            return .html(TransferWebPage.html)
        case ("GET", "/api/list"):
            return list(path)
        case ("PUT", "/api/upload"), ("POST", "/api/upload"):
            return upload(to: path, body: request.bodyURL, unzip: request.query["unzip"] == "1")
        case ("POST", "/api/mkdir"):
            return makeFolder(path)
        case ("POST", "/api/delete"):
            return delete(path)
        case ("GET", "/api/download"):
            return download(path)
        case (_, "/"), (_, "/api/list"), (_, "/api/upload"), (_, "/api/mkdir"), (_, "/api/delete"), (_, "/api/download"):
            return .error(405, "Method not allowed.")
        default:
            return .error(404, "Not found.")
        }
    }

    private func list(_ path: String) -> HTTPResponse {
        guard let directory = AppFiles.resolve(relativePath: path, in: root) else {
            return .error(400, "Invalid path.")
        }
        guard AppFiles.isDirectory(directory) else { return .error(404, "Folder not found.") }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles
            )
            let entries: [[String: Any]] = contents.map { url in
                let values = try? url.resourceValues(forKeys: Set(keys))
                return [
                    "name": url.lastPathComponent,
                    "dir": values?.isDirectory ?? false,
                    "size": values?.fileSize ?? 0,
                    "modified": values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
                ]
            }
            .sorted { a, b in
                let aIsDirectory = a["dir"] as? Bool ?? false, bIsDirectory = b["dir"] as? Bool ?? false
                if aIsDirectory != bIsDirectory { return aIsDirectory }
                return (a["name"] as? String ?? "").localizedStandardCompare(b["name"] as? String ?? "") == .orderedAscending
            }
            let relativePath = AppFiles.isSameItem(directory, root) ? "" : FolderScanner.relativePath(of: directory, in: root)
            return .json(["path": relativePath, "entries": entries])
        } catch {
            return .error(500, error.localizedDescription)
        }
    }

    private func upload(to path: String, body: URL?, unzip: Bool) -> HTTPResponse {
        guard let destination = AppFiles.resolve(relativePath: path, in: root),
              !AppFiles.isSameItem(destination, root) else {
            return .error(400, "Invalid path.")
        }
        let fileManager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

            if unzip && destination.pathExtension.lowercased() == "zip" {
                // Give the upload its real name so the unpacked folder is named after it.
                let staging = fileManager.temporaryDirectory.appending(path: "Uploads/\(UUID().uuidString)", directoryHint: .isDirectory)
                try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? fileManager.removeItem(at: staging) }
                let named = staging.appending(path: destination.lastPathComponent)
                if let body {
                    try fileManager.moveItem(at: body, to: named)
                } else {
                    try Data().write(to: named)
                }
                try AppFiles.importItem(at: named, into: folder, moveSource: true)
            } else {
                if AppFiles.isDirectory(destination) {
                    return .error(409, "A folder named “\(destination.lastPathComponent)” is already there.")
                }
                // Re-uploading a file replaces it, so updating a site just works.
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                if let body {
                    try fileManager.moveItem(at: body, to: destination)
                } else {
                    try Data().write(to: destination)
                }
            }
            filesChanged()
            return .json(["ok": true])
        } catch {
            return .error(500, error.localizedDescription)
        }
    }

    private func makeFolder(_ path: String) -> HTTPResponse {
        guard let url = AppFiles.resolve(relativePath: path, in: root), !AppFiles.isSameItem(url, root) else {
            return .error(400, "Invalid folder name.")
        }
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            filesChanged()
            return .json(["ok": true])
        } catch {
            return .error(500, error.localizedDescription)
        }
    }

    private func delete(_ path: String) -> HTTPResponse {
        guard let url = AppFiles.resolve(relativePath: path, in: root), !AppFiles.isSameItem(url, root) else {
            return .error(400, "Invalid path.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return .error(404, "Not found.") }
        do {
            try FileManager.default.removeItem(at: url)
            filesChanged()
            return .json(["ok": true])
        } catch {
            return .error(500, error.localizedDescription)
        }
    }

    private func download(_ path: String) -> HTTPResponse {
        guard let url = AppFiles.resolve(relativePath: path, in: root) else {
            return .error(400, "Invalid path.")
        }
        guard FileManager.default.fileExists(atPath: url.path) else { return .error(404, "Not found.") }

        if AppFiles.isDirectory(url) {
            do {
                let zip = try ZipArchive.archive(folder: url)
                let name = AppFiles.isSameItem(url, root) ? "HTML Viewer.zip" : zip.lastPathComponent
                return HTTPResponse(status: 200, headers: [
                    "Content-Type": "application/zip",
                    "Content-Disposition": Self.attachment(name),
                ], body: .file(zip, removeWhenDone: true))
            } catch {
                return .error(500, error.localizedDescription)
            }
        }

        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        return HTTPResponse(status: 200, headers: [
            "Content-Type": mimeType,
            "Content-Disposition": Self.attachment(url.lastPathComponent),
        ], body: .file(url, removeWhenDone: false))
    }

    private static func attachment(_ fileName: String) -> String {
        let ascii = String(fileName.unicodeScalars.map { $0.isASCII && $0 != "\"" && $0 != "\\" ? Character($0) : "_" })
        let encoded = fileName.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ascii
        return "attachment; filename=\"\(ascii)\"; filename*=UTF-8''\(encoded)"
    }
}

enum NetworkAddresses {
    /// IPv4 addresses on Wi-Fi (en*) and Personal Hotspot (bridge*) interfaces.
    static func local() -> [String] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }

        var addresses: [String] = []
        for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(interface.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let address = interface.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: host)
                if !ip.hasPrefix("169.254."), !addresses.contains(ip) { addresses.append(ip) }
            }
        }
        return addresses
    }
}
