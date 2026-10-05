import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    private enum ImportKind { case folder, file }

    @Environment(Library.self) private var library
    @State private var path: [Route] = []
    @State private var importKind = ImportKind.folder
    @State private var showingImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(
                addFolder: { present(.folder) },
                openFile: { present(.file) }
            )
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .folder(let folder):
                    FolderView(route: folder)
                case .viewer(let viewer):
                    HTMLViewerScreen(route: viewer)
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importKind == .folder ? [.folder] : [.html]
        ) { result in
            handleImport(result)
        }
        .onOpenURL { url in
            openFile(url)
        }
        .alert("Couldn't Open", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func present(_ kind: ImportKind) {
        importKind = kind
        showingImporter = true
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            if importKind == .folder {
                openFolder(url)
            } else {
                openFile(url)
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func openFolder(_ url: URL) {
        do {
            let folder = try library.addFolder(url)
            if let folderURL = folder.url {
                path = [.folder(FolderRoute(url: folderURL, root: folderURL, title: folder.name))]
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openFile(_ url: URL) {
        guard url.isFileURL else { return }
        library.beginAccessing(file: url)
        let route = ViewerRoute(files: [url], index: 0, root: url.deletingLastPathComponent())
        path.append(.viewer(route))
    }
}
