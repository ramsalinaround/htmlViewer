import SwiftUI
import WebKit

struct HTMLViewerScreen: View {
    let route: ViewerRoute

    // Created once on appear: SwiftUI may re-create this struct many times,
    // and each store owns a whole WKWebView.
    @State private var store: WebViewStore?

    var body: some View {
        Group {
            if let store {
                ViewerContent(store: store)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if store == nil {
                store = WebViewStore(files: route.files, index: route.index, root: route.root)
            }
        }
    }
}

private struct ViewerContent: View {
    @Bindable var store: WebViewStore
    @State private var sourceFile: FileItem?

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
        .navigationTitle(store.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let file = store.currentFileURL {
                    ShareLink(item: file)
                }
                moreMenu
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Back", systemImage: "chevron.backward") { store.goBack() }
                    .disabled(!store.canGoBack)
                Button("Forward", systemImage: "chevron.forward") { store.goForward() }
                    .disabled(!store.canGoForward)
                Spacer()
                if store.files.count > 1 {
                    Button("Previous File", systemImage: "arrow.up.doc") { store.previousFile() }
                        .disabled(!store.canGoToPreviousFile)
                    filePicker
                    Button("Next File", systemImage: "arrow.down.doc") { store.nextFile() }
                        .disabled(!store.canGoToNextFile)
                    Spacer()
                }
                Button("Find", systemImage: "magnifyingglass") { store.showFind() }
            }
        }
        .sheet(item: $sourceFile) { file in
            SourceView(fileURL: file.url)
        }
    }

    /// "3 of 12": tap to jump to any file in the list.
    private var filePicker: some View {
        Menu {
            Picker("File", selection: Binding(
                get: { store.position },
                set: { store.openFile(at: $0) }
            )) {
                ForEach(store.files.indices, id: \.self) { index in
                    Text(store.files[index].lastPathComponent).tag(index)
                }
            }
        } label: {
            Text("\(store.position + 1) of \(store.files.count)")
                .font(.footnote)
                .monospacedDigit()
        }
    }

    private var moreMenu: some View {
        Menu("More", systemImage: "ellipsis.circle") {
            Button("View Source", systemImage: "chevron.left.forwardslash.chevron.right") {
                sourceFile = FileItem(url: store.currentFileURL ?? store.files[store.position])
            }
            Button("Reload", systemImage: "arrow.clockwise") { store.reload() }
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
