import SwiftUI

struct FolderView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case browse = "Browse"
        case all = "All HTML Files"
        var id: Self { self }
    }

    let route: FolderRoute

    @Environment(Library.self) private var library

    @State private var mode = Mode.browse
    @State private var listing: FolderListing?
    @State private var allFiles: [URL]?
    @State private var loadError: String?
    @State private var searchText = ""

    @State private var errorMessage: String?
    @State private var showingNewFolder = false
    @State private var renameTarget: URL?
    @State private var deleteTarget: URL?
    @State private var moveTarget: FileItem?
    @State private var nameText = ""
    @State private var importKind: ImportKind?
    @State private var showingTransfer = false

    /// Files can only be changed in the app's own folder; other locations are read-only.
    private var isManaged: Bool { AppFiles.isSameItem(route.root, library.documentsURL) }

    /// Searching always looks through every subfolder.
    private var showsFlatList: Bool { mode == .all || !searchText.isEmpty }

    private var flatResults: [URL] {
        guard let allFiles else { return [] }
        guard !searchText.isEmpty else { return allFiles }
        return allFiles.filter {
            FolderScanner.relativePath(of: $0, in: route.url).localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            if showsFlatList {
                flatSection
            } else {
                browseSections
            }
        }
        .overlay { overlayContent }
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search HTML files")
        .toolbar { toolbarContent }
        .task(id: "\(route.url.path)#\(library.filesVersion)") {
            await loadListing()
            if allFiles != nil { await loadAllFiles() }
        }
        .task(id: showsFlatList) {
            if showsFlatList && allFiles == nil { await loadAllFiles() }
        }
        .refreshable {
            await loadListing()
            if showsFlatList { await loadAllFiles() } else { allFiles = nil }
        }
        .modifier(fileManagementDialogs)
    }

    // MARK: - Lists

    @ViewBuilder
    private var browseSections: some View {
        if let listing {
            if !listing.folders.isEmpty {
                Section("Folders") {
                    ForEach(listing.folders, id: \.self) { folder in
                        NavigationLink(value: Route.folder(FolderRoute(
                            url: folder,
                            root: route.root,
                            title: folder.lastPathComponent
                        ))) {
                            Label(folder.lastPathComponent, systemImage: "folder")
                        }
                        .contextMenu { itemMenu(for: folder, isFolder: true) }
                        .swipeActions { deleteSwipe(for: folder) }
                    }
                }
            }
            if !listing.files.isEmpty {
                Section("\(listing.files.count) HTML \(listing.files.count == 1 ? "File" : "Files")") {
                    ForEach(listing.files.indices, id: \.self) { index in
                        fileLink(files: listing.files, index: index, subtitle: nil)
                    }
                }
            }
            if isManaged && !listing.others.isEmpty {
                Section("Other Files") {
                    ForEach(listing.others, id: \.self) { file in
                        Label(file.lastPathComponent, systemImage: "doc")
                            .foregroundStyle(.secondary)
                            .contextMenu { itemMenu(for: file, isFolder: false) }
                            .swipeActions { deleteSwipe(for: file) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var flatSection: some View {
        let results = flatResults
        if !results.isEmpty {
            Section("\(results.count) HTML \(results.count == 1 ? "File" : "Files")") {
                ForEach(results.indices, id: \.self) { index in
                    let folder = FolderScanner.relativePath(of: results[index], in: route.url)
                        .split(separator: "/").dropLast().joined(separator: "/")
                    fileLink(files: results, index: index, subtitle: folder.isEmpty ? nil : folder)
                }
            }
        }
    }

    private func fileLink(files: [URL], index: Int, subtitle: String?) -> some View {
        NavigationLink(value: Route.viewer(ViewerRoute(files: files, index: index, root: route.root))) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(files[index].lastPathComponent)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "doc.richtext")
            }
        }
        .contextMenu { itemMenu(for: files[index], isFolder: false) }
        .swipeActions { deleteSwipe(for: files[index]) }
    }

    @ViewBuilder
    private var overlayContent: some View {
        if let loadError {
            ContentUnavailableView("Can't Read Folder", systemImage: "exclamationmark.triangle", description: Text(loadError))
        } else if showsFlatList {
            if allFiles == nil {
                ProgressView("Finding HTML files…")
            } else if flatResults.isEmpty {
                if searchText.isEmpty {
                    ContentUnavailableView("No HTML Files", systemImage: "doc.questionmark",
                                           description: Text("There are no HTML files in this folder or its subfolders."))
                } else {
                    ContentUnavailableView.search(text: searchText)
                }
            }
        } else if let listing {
            if listing.folders.isEmpty && listing.files.isEmpty && (!isManaged || listing.others.isEmpty) {
                if isManaged {
                    ContentUnavailableView {
                        Label("No Files Yet", systemImage: "folder")
                    } description: {
                        Text("Share HTML or .zip files to HTML Viewer from other apps, import them with +, or use Wi-Fi Transfer from a computer.")
                    } actions: {
                        Button("Import Files…") { importKind = .files }
                        Button("Wi-Fi Transfer") { showingTransfer = true }
                    }
                } else {
                    ContentUnavailableView("No HTML Files", systemImage: "folder",
                                           description: Text("This folder has no HTML files or subfolders."))
                }
            }
        } else {
            ProgressView()
        }
    }

    // MARK: - Sharing and file management

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if isManaged {
                Menu("Add", systemImage: "plus") {
                    Button("New Folder", systemImage: "folder.badge.plus") {
                        nameText = ""
                        showingNewFolder = true
                    }
                    Button("Import Files…", systemImage: "doc.badge.plus") { importKind = .files }
                    Button("Import Folder…", systemImage: "folder") { importKind = .folder }
                    Divider()
                    Button("Wi-Fi Transfer", systemImage: "wifi") { showingTransfer = true }
                }
            }
            ShareLink(item: FolderArchive(url: route.url), preview: SharePreview("\(route.title).zip")) {
                Label("Share Folder as ZIP", systemImage: "square.and.arrow.up")
            }
        }
    }

    @ViewBuilder
    private func itemMenu(for url: URL, isFolder: Bool) -> some View {
        if isFolder {
            ShareLink(item: FolderArchive(url: url), preview: SharePreview("\(url.lastPathComponent).zip")) {
                Label("Share as ZIP", systemImage: "square.and.arrow.up")
            }
        } else {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
        if isManaged {
            Button("Rename", systemImage: "pencil") {
                nameText = url.lastPathComponent
                renameTarget = url
            }
            Button("Move…", systemImage: "folder") { moveTarget = FileItem(url: url) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = url }
        }
    }

    @ViewBuilder
    private func deleteSwipe(for url: URL) -> some View {
        if isManaged {
            Button("Delete", systemImage: "trash") { deleteTarget = url }
                .tint(.red)
        }
    }

    private var fileManagementDialogs: FileManagementDialogs {
        FileManagementDialogs(
            folderURL: route.url,
            root: route.root,
            errorMessage: $errorMessage,
            showingNewFolder: $showingNewFolder,
            renameTarget: $renameTarget,
            deleteTarget: $deleteTarget,
            moveTarget: $moveTarget,
            nameText: $nameText,
            importKind: $importKind,
            showingTransfer: $showingTransfer,
            perform: perform
        )
    }

    /// Runs a file operation off the main thread, then refreshes every open list.
    private func perform(_ operation: @escaping @Sendable () throws -> Void) {
        Task {
            do {
                try await Task.detached(operation: operation).value
            } catch {
                errorMessage = error.localizedDescription
            }
            library.filesDidChange()
        }
    }

    // MARK: - Loading

    private func loadListing() async {
        let url = route.url
        let result = await Task.detached { Result { try FolderScanner.listing(of: url) } }.value
        switch result {
        case .success(let listing):
            self.listing = listing
            loadError = nil
        case .failure(let error):
            loadError = error.localizedDescription
        }
    }

    private func loadAllFiles() async {
        let url = route.url
        allFiles = await Task.detached { FolderScanner.allHTMLFiles(under: url) }.value
    }
}

private enum ImportKind: Identifiable {
    case files, folder
    var id: Self { self }
}

/// The alerts and sheets behind New Folder, Rename, Move, Delete and Import.
private struct FileManagementDialogs: ViewModifier {
    let folderURL: URL
    let root: URL
    @Binding var errorMessage: String?
    @Binding var showingNewFolder: Bool
    @Binding var renameTarget: URL?
    @Binding var deleteTarget: URL?
    @Binding var moveTarget: FileItem?
    @Binding var nameText: String
    @Binding var importKind: ImportKind?
    @Binding var showingTransfer: Bool
    let perform: @MainActor (@escaping @Sendable () throws -> Void) -> Void

    @Environment(Library.self) private var library

    func body(content: Content) -> some View {
        content
            .alert("New Folder", isPresented: $showingNewFolder) {
                TextField("Name", text: $nameText)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = nameText, folder = folderURL
                    perform { try AppFiles.createFolder(named: name, in: folder) }
                }
            }
            .alert("Rename", isPresented: isPresent($renameTarget), presenting: renameTarget) { url in
                TextField("Name", text: $nameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let name = nameText
                    perform { try AppFiles.rename(url, to: name) }
                }
            }
            .confirmationDialog(
                Text("Delete “\(deleteTarget?.lastPathComponent ?? "")”?"),
                isPresented: isPresent($deleteTarget),
                titleVisibility: .visible,
                presenting: deleteTarget
            ) { url in
                Button("Delete", role: .destructive) {
                    perform { try AppFiles.delete(url) }
                }
            } message: { url in
                Text(AppFiles.isDirectory(url)
                     ? "The folder and everything in it will be deleted. This can't be undone."
                     : "This can't be undone.")
            }
            .sheet(item: $moveTarget) { item in
                MoveSheet(item: item.url, root: root) { destination in
                    perform { try AppFiles.move(item.url, into: destination) }
                }
            }
            .sheet(item: $importKind) { kind in
                DocumentPicker(
                    contentTypes: kind == .files ? [.item] : [.folder],
                    allowsMultipleSelection: kind == .files,
                    onPick: { urls in
                        let folder = folderURL
                        perform { for url in urls { try AppFiles.importItem(at: url, into: folder) } }
                    },
                    onDismiss: { importKind = nil }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showingTransfer) {
                TransferView()
                    .environment(library)
            }
            .alert("Something Went Wrong", isPresented: isPresent($errorMessage)) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func isPresent<T>(_ binding: Binding<T?>) -> Binding<Bool> {
        Binding(get: { binding.wrappedValue != nil }, set: { if !$0 { binding.wrappedValue = nil } })
    }
}
