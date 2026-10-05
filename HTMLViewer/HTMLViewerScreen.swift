import SwiftUI
import WebKit

/// A full-screen, lightweight browser: the page gets the whole display and
/// a small floating control bar slides away while you read.
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
                Color(uiColor: .systemBackground).ignoresSafeArea()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden()
        .statusBarHidden()
        .onAppear {
            if store == nil {
                store = WebViewStore(files: route.files, index: route.index, root: route.root, startURL: route.startURL)
            }
        }
    }
}

private struct ViewerContent: View {
    @Bindable var store: WebViewStore
    @Environment(\.dismiss) private var dismiss
    @State private var sourceFile: FileItem?
    @State private var showingAddress = false
    @State private var addressText = ""

    var body: some View {
        WebView(webView: store.webView)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                if store.isLoading {
                    ProgressView(value: store.progress)
                        .progressViewStyle(.linear)
                        .scaleEffect(x: 1, y: 0.6, anchor: .top)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) { controls }
            .animation(.default, value: store.isLoading)
            .persistentSystemOverlays(store.controlsHidden ? .hidden : .automatic)
            .sheet(item: $sourceFile) { file in
                SourceView(fileURL: file.url)
            }
            .alert("Go to Address", isPresented: $showingAddress) {
                TextField("Website or search", text: $addressText)
                    .keyboardType(.webSearch)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Cancel", role: .cancel) {}
                Button("Go") { store.go(to: addressText) }
            }
    }

    // MARK: - Floating controls

    private var controls: some View {
        ZStack(alignment: .bottom) {
            controlBar
                .offset(y: store.controlsHidden ? 140 : 0)
                .opacity(store.controlsHidden ? 0 : 1)
                .allowsHitTesting(!store.controlsHidden)

            if store.controlsHidden {
                Button {
                    store.setControlsHidden(false)
                } label: {
                    Capsule()
                        .fill(.secondary.opacity(0.6))
                        .frame(width: 40, height: 5)
                        .frame(width: 120, height: 26)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Show Controls")
                .transition(.opacity)
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 0) {
            barButton("Close", systemImage: "xmark") { dismiss() }
            Divider().frame(height: 22)
            barButton("Back", systemImage: "chevron.backward") { store.goBack() }
                .disabled(!store.canGoBack)
            barButton("Forward", systemImage: "chevron.forward") { store.goForward() }
                .disabled(!store.canGoForward)

            if store.files.count > 1 && store.currentFileURL != nil {
                barButton("Previous File", systemImage: "arrow.up.doc") { store.previousFile() }
                    .disabled(!store.canGoToPreviousFile)
                filePicker
                barButton("Next File", systemImage: "arrow.down.doc") { store.nextFile() }
                    .disabled(!store.canGoToNextFile)
            } else {
                Text(store.title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 170)
                    .padding(.horizontal, 6)
            }

            moreMenu
        }
        .padding(.horizontal, 4)
        .frame(height: 48)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.4), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.bottom, 6)
        .padding(.horizontal, 8)
    }

    private func barButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 42, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }

    /// "3 / 12": tap to jump to any file in the list.
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
            Text("\(store.position + 1) / \(store.files.count)")
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .padding(.horizontal, 4)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("File \(store.position + 1) of \(store.files.count)")
    }

    private var moreMenu: some View {
        Menu {
            Section {
                Button("Go to Address…", systemImage: "globe") {
                    addressText = store.isWebPage ? store.currentURL?.absoluteString ?? "" : ""
                    showingAddress = true
                }
                if let file = store.currentFileURL {
                    ShareLink(item: file) { Label("Share", systemImage: "square.and.arrow.up") }
                } else if store.isWebPage, let url = store.currentURL {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Button("Open in Safari", systemImage: "safari") { UIApplication.shared.open(url) }
                }
            }
            Section {
                Button("Find on Page", systemImage: "magnifyingglass") { store.showFind() }
                if let file = store.currentFileURL {
                    Button("View Source", systemImage: "chevron.left.forwardslash.chevron.right") {
                        sourceFile = FileItem(url: file)
                    }
                }
                Button("Reload", systemImage: "arrow.clockwise") { store.reload() }
                Button("Hide Controls", systemImage: "arrow.down.right.and.arrow.up.left") {
                    store.setControlsHidden(true)
                }
            }
            Section("Page Size") {
                ControlGroup {
                    Button("Smaller", systemImage: "minus.magnifyingglass") { store.zoomOut() }
                    Button("\(Int((store.pageZoom * 100).rounded()))%") { store.pageZoom = 1 }
                    Button("Larger", systemImage: "plus.magnifyingglass") { store.zoomIn() }
                }
            }
            Section {
                Toggle(isOn: $store.autoHidesControls) {
                    Label("Auto-Hide Controls", systemImage: "rectangle.bottomhalf.inset.filled")
                }
                Toggle(isOn: $store.edgeToEdge) {
                    Label("Edge to Edge", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                Toggle(isOn: $store.prefersDesktopSite) {
                    Label("Desktop Site", systemImage: "desktopcomputer")
                }
                Toggle(isOn: $store.javaScriptEnabled) {
                    Label("JavaScript", systemImage: "curlybraces")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .medium))
                .frame(width: 42, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("More")
    }
}

private struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView { webView }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
