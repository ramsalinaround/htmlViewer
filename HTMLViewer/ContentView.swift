import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(Library.self) private var library
    @State private var path: [Route] = []
    @State private var importKind = ImportKind.folder
    @State private var showingImporter = false
    @State private var errorMessage: String?

    private enum ImportKind { case folder, file }

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
            receive(url)
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

    /// Opens a file picked with "Open Single File…" where it is, without copying it.
    private func openFile(_ url: URL) {
        library.beginAccessing(file: url)
        let route = ViewerRoute(files: [url], index: 0, root: url.deletingLastPathComponent())
        path.append(.viewer(route))
    }

    /// A file shared to the app from another app (Mail, Messages, AirDrop,
    /// Files…): keep a copy in the app's folder, unpacking zips, then show it.
    private func receive(_ url: URL) {
        guard url.isFileURL else { return }
        let documents = library.documentsURL
        Task {
            do {
                let saved = try await Task.detached { try Self.save(url, in: documents) }.value
                library.filesDidChange()
                show(saved, in: documents)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private nonisolated static func save(_ url: URL, in documents: URL) throws -> URL {
        let inbox = documents.appending(path: "Inbox")
        let isZip = url.pathExtension.lowercased() == "zip"
        if AppFiles.isInside(url, documents) && !AppFiles.isInside(url, inbox) && !isZip {
            return url  // Already in the app's folder.
        }
        // Copies iOS made for us in Documents/Inbox are moved, not duplicated.
        let fromInbox = AppFiles.isInside(url, inbox)
        let saved = try AppFiles.importItem(
            at: url,
            into: isZip && AppFiles.isInside(url, documents) && !fromInbox ? url.deletingLastPathComponent() : documents,
            moveSource: fromInbox
        )
        if fromInbox { AppFiles.removeIfEmpty(inbox) }
        return saved
    }

    private func show(_ item: URL, in documents: URL) {
        if AppFiles.isDirectory(item) {
            path = [.folder(FolderRoute(url: item, root: documents, title: item.lastPathComponent))]
        } else if FolderScanner.isHTML(item) {
            // Let Previous / Next step through the other pages next to it.
            let siblings = (try? FolderScanner.listing(of: item.deletingLastPathComponent()).files) ?? []
            let index = siblings.firstIndex { $0.lastPathComponent == item.lastPathComponent }
            let route = index.map { ViewerRoute(files: siblings, index: $0, root: documents) }
                ?? ViewerRoute(files: [item], index: 0, root: documents)
            path = [.viewer(route)]
        } else {
            path = [.folder(FolderRoute(url: documents, root: documents, title: "HTML Viewer"))]
        }
    }
}
