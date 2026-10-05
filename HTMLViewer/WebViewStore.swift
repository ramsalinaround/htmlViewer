import Observation
import UIKit
import WebKit

/// Owns the `WKWebView` for one open document and mirrors its state for SwiftUI.
@MainActor
@Observable
final class WebViewStore: NSObject {
    let webView: WKWebView

    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0

    var javaScriptEnabled = true {
        didSet { webView.reload() }
    }

    @ObservationIgnored private let startURL: URL
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(data: Data, fileURL: URL?) {
        let documentURL = fileURL ?? URL(fileURLWithPath: "/Untitled.html")
        let handler = LocalFileSchemeHandler(documentURL: documentURL, documentData: data)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(handler, forURLScheme: LocalFileSchemeHandler.scheme)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isFindInteractionEnabled = true
        webView.isInspectable = true
        startURL = LocalFileSchemeHandler.webURL(for: documentURL)

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebView()
        webView.load(URLRequest(url: startURL))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func goHome() { webView.load(URLRequest(url: startURL)) }

    func showFind() {
        webView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    private func observeWebView() {
        observations = [
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
