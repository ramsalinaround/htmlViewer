import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves files from disk to the web view through a custom URL scheme.
///
/// Loading through the app process instead of `loadFileURL` lets pages from
/// any Files location (iCloud Drive, other apps, external providers) render
/// reliably, and relative links to CSS, scripts, images and other pages
/// resolve against the folder the user granted access to. Requests outside
/// that folder are refused.
@MainActor
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "htmlviewer-file"

    private let rootPath: String
    private var activeTasks = Set<ObjectIdentifier>()

    init(root: URL) {
        let path = root.standardizedFileURL.path(percentEncoded: false)
        rootPath = path.hasSuffix("/") ? path : path + "/"
    }

    /// The URL the web view should load for a file on disk.
    static func webURL(for fileURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "local"
        components.path = fileURL.standardizedFileURL.path(percentEncoded: false)
        return components.url!
    }

    /// The file on disk behind a URL produced by `webURL(for:)`.
    static func fileURL(for webURL: URL) -> URL? {
        guard webURL.scheme == scheme else { return nil }
        return URL(fileURLWithPath: webURL.path(percentEncoded: false)).standardizedFileURL
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url,
              let fileURL = Self.fileURL(for: requestURL) else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }
        guard fileURL.path(percentEncoded: false).hasPrefix(rootPath) else {
            respond(to: urlSchemeTask, url: requestURL, status: 403)
            return
        }

        let taskID = ObjectIdentifier(urlSchemeTask)
        activeTasks.insert(taskID)
        Task {
            let result = await Task.detached { Result { try FileAccess.read(fileURL) } }.value
            guard activeTasks.remove(taskID) != nil else { return }
            switch result {
            case .success(let data):
                respond(to: urlSchemeTask, url: requestURL, status: 200, data: data,
                        contentType: Self.contentType(for: fileURL, data: data))
            case .failure:
                respond(to: urlSchemeTask, url: requestURL, status: 404)
            }
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        activeTasks.remove(ObjectIdentifier(urlSchemeTask))
    }

    private func respond(to task: WKURLSchemeTask, url: URL, status: Int, data: Data = Data(), contentType: String? = nil) {
        var headers = ["Content-Length": String(data.count)]
        headers["Content-Type"] = contentType
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    private static func contentType(for fileURL: URL, data: Data) -> String {
        let type = UTType(filenameExtension: fileURL.pathExtension)
        let mimeType = type?.preferredMIMEType ?? "application/octet-stream"
        // Files without a <meta charset> would otherwise be decoded as
        // Latin-1; prefer UTF-8 whenever the bytes are valid UTF-8.
        let isText = type?.conforms(to: .text) ?? false
        if isText, String(data: data, encoding: .utf8) != nil {
            return "\(mimeType); charset=utf-8"
        }
        return mimeType
    }
}
