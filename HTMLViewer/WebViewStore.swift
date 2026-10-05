import Observation
import UIKit
import WebKit

/// Owns the `WKWebView` for one viewer and mirrors its state for SwiftUI.
@MainActor
@Observable
final class WebViewStore: NSObject {
    let webView: WKWebView

    /// The files Previous / Next step through.
    let files: [URL]
    /// Index in `files` of the page on screen, or of the last one opened
    /// from the list when a link led elsewhere.
    private(set) var position: Int
    private(set) var currentFileURL: URL?

    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0

    var javaScriptEnabled = true {
        didSet { webView.reload() }
    }

    var title: String {
        (currentFileURL ?? files[position]).lastPathComponent
    }

    var canGoToPreviousFile: Bool { position > 0 }
    var canGoToNextFile: Bool { position < files.count - 1 }

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(files: [URL], index: Int, root: URL) {
        self.files = files.map(\.standardizedFileURL)
        position = min(max(index, 0), files.count - 1)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalFileSchemeHandler(root: root), forURLScheme: LocalFileSchemeHandler.scheme)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isFindInteractionEnabled = true
        webView.isInspectable = true

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebView()
        openFile(at: position)
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func openFile(at index: Int) {
        guard files.indices.contains(index) else { return }
        position = index
        webView.load(URLRequest(url: LocalFileSchemeHandler.webURL(for: files[index])))
    }

    func previousFile() { openFile(at: position - 1) }
    func nextFile() { openFile(at: position + 1) }

    func showFind() {
        webView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    private func urlDidChange(_ url: URL?) {
        currentFileURL = url.flatMap(LocalFileSchemeHandler.fileURL(for:))
        if let path = currentFileURL?.path,
           let index = files.firstIndex(where: { $0.path == path }) {
            position = index
        }
    }

    private func observeWebView() {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.urlDidChange(webView.url) }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.isLoading = webView.isLoading }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.progress = webView.estimatedProgress }
            },
        ]
    }

    private func openExternally(_ url: URL) {
        UIApplication.shared.open(url)
    }
}

extension WebViewStore: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        preferences.allowsContentJavaScript = javaScriptEnabled

        guard let url = navigationAction.request.url else {
            return (.cancel, preferences)
        }

        switch url.scheme?.lowercased() {
        case LocalFileSchemeHandler.scheme, "about", "data", "blob":
            return (.allow, preferences)
        case "http", "https":
            // Links the user taps in the page open in Safari; frames and
            // scripted navigations stay inside the viewer.
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if navigationAction.navigationType == .linkActivated && isMainFrame {
                openExternally(url)
                return (.cancel, preferences)
            }
            return (.allow, preferences)
        default:
            // mailto:, tel:, sms:, maps and other app links.
            openExternally(url)
            return (.cancel, preferences)
        }
    }
}

extension WebViewStore: WKUIDelegate {
    /// Handles `target="_blank"` links and `window.open`.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            if url.scheme == LocalFileSchemeHandler.scheme {
                webView.load(navigationAction.request)
            } else {
                openExternally(url)
            }
        }
        return nil
    }
}
