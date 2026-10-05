import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the opened document (and, when readable, files next to it) to the
/// web view through a custom URL scheme.
///
/// Loading through the app process instead of `loadFileURL` means documents
/// opened from any Files location (iCloud Drive, other apps, external
/// providers) render reliably, while relative links to CSS, scripts and
/// images still resolve whenever the app is allowed to read them.
final class LocalFileSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "htmlviewer-file"

    private let documentURL: URL
    private let documentData: Data

    init(documentURL: URL, documentData: Data) {
        self.documentURL = documentURL.standardizedFileURL
        self.documentData = documentData
    }

    /// The URL the web view should load for a file on disk.
    static func webURL(for fileURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "local"
        components.path = fileURL.standardizedFileURL.path(percentEncoded: false)
        return components.url!
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL))
            return
        }

        let fileURL = URL(fileURLWithPath: requestURL.path(percentEncoded: false)).standardizedFileURL
        let data: Data?
        if fileURL.path == documentURL.path {
            data = documentData
        } else {
            data = try? Data(contentsOf: fileURL)
        }

        guard let data else {
            let response = HTTPURLResponse(url: requestURL, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(Data())
            urlSchemeTask.didFinish()
            return
        }

        let response = HTTPURLResponse(
            url: requestURL,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": Self.contentType(for: fileURL, data: data),
                "Content-Length": String(data.count),
                "Access-Control-Allow-Origin": "*",
            ]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        // Requests are answered synchronously, so there is nothing to cancel.
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
