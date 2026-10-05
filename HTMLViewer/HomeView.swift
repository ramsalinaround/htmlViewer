import SwiftUI

struct HomeView: View {
    let addFolder: () -> Void
    let openFile: () -> Void

    @Environment(Library.self) private var library
    @State private var showingTransfer = false

    var body: some View {
        List {
            Section {
                ForEach(library.folders) { folder in
                    folderRow(folder)
                }
                .onDelete { library.removeFolders(at: $0) }
                .onMove { library.moveFolders(from: $0, to: $1) }

                Button(action: addFolder) {
                    Label("Add Folder…", systemImage: "folder.badge.plus")
                }
            } header: {
                Text("Folders")
            } footer: {
                if library.folders.isEmpty {
                    Text("Pick a folder from iCloud Drive, On My iPhone, or any other location to browse every HTML file inside it.")
                }
            }

            Section {
                NavigationLink(value: Route.folder(FolderRoute(
                    url: library.documentsURL,
                    root: library.documentsURL,
                    title: "HTML Viewer"
                ))) {
                    Label("HTML Viewer Folder", systemImage: "iphone")
                }
                Button {
                    showingTransfer = true
                } label: {
                    Label("Wi-Fi Transfer", systemImage: "wifi")
                }
            } header: {
                Text("On This Device")
            } footer: {
                Text("Files shared to HTML Viewer from other apps are saved here. You can also reach this folder from the Files app, Finder, or a computer browser via Wi-Fi Transfer.")
            }

            Section {
                Button(action: openFile) {
                    Label("Open Single File…", systemImage: "doc.richtext")
                }
            }
        }
        .navigationTitle("HTML Viewer")
        .toolbar {
            if !library.folders.isEmpty {
                EditButton()
            }
        }
        .sheet(isPresented: $showingTransfer) {
            TransferView()
                .environment(library)
        }
    }

    @ViewBuilder
    private func folderRow(_ folder: Library.Folder) -> some View {
        if let url = folder.url {
            NavigationLink(value: Route.folder(FolderRoute(url: url, root: url, title: folder.name))) {
                Label(folder.name, systemImage: "folder")
            }
            .contextMenu {
                ShareLink(item: FolderArchive(url: url), preview: SharePreview("\(folder.name).zip")) {
                    Label("Share as ZIP", systemImage: "square.and.arrow.up")
                }
            }
        } else {
            Label {
                VStack(alignment: .leading) {
                    Text(folder.name)
                    Text("Unavailable. Remove it and add it again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "folder.badge.questionmark")
            }
            .foregroundStyle(.secondary)
        }
    }
}
