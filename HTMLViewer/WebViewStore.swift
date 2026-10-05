import Observation
import SwiftUI
import UIKit
import WebKit

/// Owns the `WKWebView` for one viewer and mirrors its state for SwiftUI.
@MainActor
@Observable
final class WebViewStore: NSObject {
    let webView: WKWebView

    /// The files Previous / Next step through. Empty when browsing a web address.
    let files: [URL]
    /// Index in `files` of the page on screen, or of the last one opened
    /// from the list when a link led elsewhere.
    private(set) var position: Int
    private(set) var currentURL: URL?
    private(set) var currentFileURL: URL?
    private(set) var pageTitle: String?

    private(set) var canGoBack = false
    private(set) var canGoForward = false
    private(set) var isLoading = false
    private(set) var progress = 0.0

    /// Whether the floating controls are tucked away to give the page the whole screen.
    private(set) var controlsHidden = false

    var javaScriptEnabled = true {
        didSet { webView.reload() }
    }

    // Viewing preferences, remembered across pages and launches.

    var pageZoom = ViewerSettings.pageZoom {
        didSet {
            webView.pageZoom = pageZoom
            ViewerSettings.pageZoom = pageZoom
        }
    }

    var prefersDesktopSite = ViewerSettings.prefersDesktopSite {
        didSet {
            ViewerSettings.prefersDesktopSite = prefersDesktopSite
            webView.reload()
        }
    }

    var autoHidesControls = ViewerSettings.autoHidesControls {
        didSet {
            ViewerSettings.autoHidesControls = autoHidesControls
            if !autoHidesControls { setControlsHidden(false) }
        }
    }

    /// Lets the page draw under the notch and home indicator too.
    var edgeToEdge = ViewerSettings.edgeToEdge {
        didSet {
            ViewerSettings.edgeToEdge = edgeToEdge
            applyInsets()
        }
    }

    var title: String {
        if let currentFileURL { return currentFileURL.lastPathComponent }
        if let pageTitle, !pageTitle.isEmpty { return pageTitle }
        return currentURL?.host() ?? files.first?.lastPathComponent ?? ""
    }

    var isWebPage: Bool {
        ["http", "https"].contains(currentURL?.scheme?.lowercased() ?? "")
    }

    var canGoToPreviousFile: Bool { position > 0 }
    var canGoToNextFile: Bool { position < files.count - 1 }

    /// Room at the end of the page so the last lines can scroll clear of the floating controls.
    static let controlsClearance: CGFloat = 64

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var scrollTravel: CGFloat = 0
    /// A local page the app itself asked for; web pages may not open local files.
    @ObservationIgnored private var appRequestedURL: URL?

    init(files: [URL], index: Int, root: URL, startURL: URL? = nil) {
        self.files = files.map(\.standardizedFileURL)
        position = files.isEmpty ? 0 : min(max(index, 0), files.count - 1)

        let configuration = WKWebViewConfiguration()
        configuration.setURLSchemeHandler(LocalFileSchemeHandler(root: root), forURLScheme: LocalFileSchemeHandler.scheme)
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []

        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isFindInteractionEnabled = true
        webView.isInspectable = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.pageZoom = ViewerSettings.pageZoom

        super.init()

        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(pullToRefresh), for: .valueChanged)
        webView.scrollView.refreshControl = refreshControl
        applyInsets()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        observeWebView()

        if let startURL, files.isEmpty {
            load(startURL)
        } else {
            openFile(at: position)
        }
    }

    // MARK: - Navigation

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func openFile(at index: Int) {
        guard files.indices.contains(index) else { return }
        position = index
        load(LocalFileSchemeHandler.webURL(for: files[index]))
    }

    func previousFile() { openFile(at: position - 1) }
    func nextFile() { openFile(at: position + 1) }

    /// Opens what the user typed: a web address, or a web search.
    func go(to address: String) {
        if let url = Self.url(fromAddress: address) { load(url) }
    }

    func showFind() {
        webView.findInteraction?.presentFindNavigator(showingReplace: false)
    }

    private func load(_ url: URL) {
        appRequestedURL = url
        webView.load(URLRequest(url: url))
    }

    /// `example.com` → https://example.com, `two words` → a DuckDuckGo search.
    nonisolated static func url(fromAddress text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host() != nil {
            return url
        }
        if !text.contains(" "), text.contains("."), !text.hasPrefix("."),
           let url = URL(string: "https://" + text), url.host() != nil {
            return url
        }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }

    // MARK: - Page size

    static let zoomLevels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3]

    func zoomIn() {
        if let next = Self.zoomLevels.first(where: { $0 > pageZoom + 0.001 }) { pageZoom = next }
    }

    func zoomOut() {
        if let next = Self.zoomLevels.last(where: { $0 < pageZoom - 0.001 }) { pageZoom = next }
    }

    // MARK: - Controls

    func setControlsHidden(_ hidden: Bool) {
        guard controlsHidden != hidden else { return }
        withAnimation(.snappy(duration: 0.25)) { controlsHidden = hidden }
    }

    /// Hides the controls while reading down the page and brings them back
    /// when scrolling up or reaching either end, like Safari.
    private func scrollViewDidScroll(_ scrollView: UIScrollView, from old: CGPoint, to new: CGPoint) {
        guard autoHidesControls, !scrollView.isZooming,
              scrollView.isTracking || scrollView.isDecelerating else { return }

        let top = -scrollView.adjustedContentInset.top
        let bottom = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
        if new.y <= top + 4 || new.y >= bottom - 4 {
            scrollTravel = 0
            setControlsHidden(false)
            return
        }

        let delta = new.y - old.y
        if (delta > 0) != (scrollTravel > 0) { scrollTravel = 0 }
        scrollTravel += delta
        if scrollTravel > 30 {
            setControlsHidden(true)
        } else if scrollTravel < -30 {
            setControlsHidden(false)
        }
    }

    private func applyInsets() {
        let scrollView = webView.scrollView
        scrollView.contentInsetAdjustmentBehavior = edgeToEdge ? .never : .automatic
        scrollView.contentInset.bottom = Self.controlsClearance
        scrollView.verticalScrollIndicatorInsets.bottom = Self.controlsClearance
    }

    @objc private func pullToRefresh() {
        webView.reload()
    }

    // MARK: - Observation

    private func urlDidChange(_ url: URL?) {
        currentURL = url
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
            webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.pageTitle = webView.title }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoBack = webView.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.canGoForward = webView.canGoForward }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    self?.isLoading = webView.isLoading
                    if !webView.isLoading { webView.scrollView.refreshControl?.endRefreshing() }
                }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.progress = webView.estimatedProgress }
            },
            webView.scrollView.observe(\.contentOffset, options: [.old, .new]) { [weak self] scrollView, change in
                guard let old = change.oldValue, let new = change.newValue else { return }
                MainActor.assumeIsolated { self?.scrollViewDidScroll(scrollView, from: old, to: new) }
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
        preferences.preferredContentMode = prefersDesktopSite ? .desktop : .mobile

        guard let url = navigationAction.request.url else {
            return (.cancel, preferences)
        }
        let isAppRequest = url == appRequestedURL
        if isAppRequest { appRequestedURL = nil }

        switch url.scheme?.lowercased() {
        case LocalFileSchemeHandler.scheme:
            // A web page may not navigate into the user's local files.
            let onWebPage = ["http", "https"].contains(webView.url?.scheme?.lowercased() ?? "")
            if onWebPage && !isAppRequest && navigationAction.navigationType != .backForward {
                return (.cancel, preferences)
            }
            return (.allow, preferences)
        case "http", "https", "about", "data", "blob":
            return (.allow, preferences)
        default:
            // mailto:, tel:, sms:, maps and other app links.
            openExternally(url)
            return (.cancel, preferences)
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        setControlsHidden(false)
    }
}

extension WebViewStore: WKUIDelegate {
    /// Opens `target="_blank"` links and `window.open` in the same view.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

/// Viewer preferences stored in UserDefaults.
enum ViewerSettings {
    private static let defaults = UserDefaults.standard

    static var pageZoom: Double {
        get { defaults.object(forKey: "viewer.pageZoom") as? Double ?? 1 }
        set { defaults.set(newValue, forKey: "viewer.pageZoom") }
    }

    static var prefersDesktopSite: Bool {
        get { defaults.bool(forKey: "viewer.desktopSite") }
        set { defaults.set(newValue, forKey: "viewer.desktopSite") }
    }

    static var autoHidesControls: Bool {
        get { defaults.object(forKey: "viewer.autoHideControls") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "viewer.autoHideControls") }
    }

    static var edgeToEdge: Bool {
        get { defaults.bool(forKey: "viewer.edgeToEdge") }
        set { defaults.set(newValue, forKey: "viewer.edgeToEdge") }
    }
}
