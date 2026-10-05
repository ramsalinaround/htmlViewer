import SwiftUI

struct FolderView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case browse = "Browse"
        case all = "All HTML Files"
        var id: Self { self }
    }

    let route: FolderRoute

    @State private var mode = Mode.browse
    @State private var listing: FolderListing?
    @State private var allFiles: [URL]?
    @State private var loadError: String?
    @State private var searchText = ""

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
        .task(id: route.url) { await loadListing() }
        .task(id: showsFlatList) {
            if showsFlatList && allFiles == nil { await loadAllFiles() }
        }
        .refreshable {
            await loadListing()
            if showsFlatList { await loadAllFiles() } else { allFiles = nil }
        }
    }

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
            if listing.folders.isEmpty && listing.files.isEmpty {
                ContentUnavailableView("No HTML Files", systemImage: "folder",
                                       description: Text("This folder has no HTML files or subfolders."))
            }
        } else {
            ProgressView()
        }
    }

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
