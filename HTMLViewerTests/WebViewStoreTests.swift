import XCTest
@testable import HTMLViewer

@MainActor
final class WebViewStoreTests: XCTestCase {
    func testAddressParsing() {
        XCTAssertEqual(WebViewStore.url(fromAddress: "https://example.com/a?b=1")?.absoluteString, "https://example.com/a?b=1")
        XCTAssertEqual(WebViewStore.url(fromAddress: "  example.com  ")?.absoluteString, "https://example.com")
        XCTAssertEqual(WebViewStore.url(fromAddress: "developer.apple.com/documentation")?.absoluteString,
                       "https://developer.apple.com/documentation")

        let search = WebViewStore.url(fromAddress: "swift web view")
        XCTAssertEqual(search?.host(), "duckduckgo.com")
        XCTAssertEqual(URLComponents(url: search!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "swift web view")

        XCTAssertEqual(WebViewStore.url(fromAddress: "localhost")?.host(), "duckduckgo.com")
        XCTAssertNil(WebViewStore.url(fromAddress: "   "))
    }

    func testPageZoomStepsAndLimits() {
        let saved = ViewerSettings.pageZoom
        defer { ViewerSettings.pageZoom = saved }
        ViewerSettings.pageZoom = 1

        let store = WebViewStore(files: [], index: 0, root: FileManager.default.temporaryDirectory)
        XCTAssertEqual(store.pageZoom, 1)

        store.zoomOut()
        XCTAssertEqual(store.pageZoom, 0.9)
        XCTAssertEqual(store.webView.pageZoom, 0.9, accuracy: 0.001)
        XCTAssertEqual(ViewerSettings.pageZoom, 0.9, "zoom is remembered")

        for _ in 0..<20 { store.zoomOut() }
        XCTAssertEqual(store.pageZoom, WebViewStore.zoomLevels.first)
        for _ in 0..<30 { store.zoomIn() }
        XCTAssertEqual(store.pageZoom, WebViewStore.zoomLevels.last)
    }
}
