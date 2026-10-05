import SwiftUI
import WebKit

struct HTMLViewerScreen: View {
    let data: Data
    let fileURL: URL?

    @State private var store: WebViewStore
    @State private var showingSource = false

    init(data: Data, fileURL: URL?) {
        self.data = data
        self.fileURL = fileURL
        _store = State(initialValue: WebViewStore(data: data, fileURL: fileURL))
    }

    var body: some View {
        ZStack(alignment: .top) {
            WebView(webView: store.webView)

            if store.isLoading {
                ProgressView(value: store.progress)
                    .progressViewStyle(.linear)
                    .transition(.opacity)
            }
        }
        .animation(.default, value: store.isLoading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let fileURL {
                    ShareLink(item: fileURL)
                }
                moreMenu
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Back", systemImage: "chevron.backward") { store.goBack() }
                    .disabled(!store.canGoBack)
                Button("Forward", systemImage: "chevron.forward") { store.goForward() }
                    .disabled(!store.canGoForward)
                Spacer()
                Button("Find", systemImage: "magnifyingglass") { store.showFind() }
                Spacer()
                Button("Reload", systemImage: "arrow.clockwise") { store.reload() }
            }
        }
        .sheet(isPresented: $showingSource) {
            SourceView(source: String(decoding: data, as: UTF8.self),
                       title: fileURL?.lastPathComponent ?? "Source")
        }
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Button("View Source", systemImage: "chevron.left.forwardslash.chevron.right") {
                showingSource = true
            }
            Button("Back to Start", systemImage: "house") { store.goHome() }
            Toggle(isOn: $store.javaScriptEnabled) {
                Label("JavaScript", systemImage: "curlybraces")
            }
        }
    }
}

private struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
