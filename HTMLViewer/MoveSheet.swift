import SwiftUI

/// Picks a destination folder inside the app's folder.
struct MoveSheet: View {
    let item: URL
    let root: URL
    let onMove: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var destinations: [Destination]?

    private struct Destination: Identifiable {
        let url: URL
        let name: String
        let depth: Int
        let isCurrent: Bool
        var id: URL { url }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let destinations {
                    List(destinations) { destination in
                        Button {
                            onMove(destination.url)
                            dismiss()
                        } label: {
                            Label(destination.name, systemImage: destination.depth == 0 ? "iphone" : "folder")
                                .padding(.leading, CGFloat(destination.depth) * 18)
                        }
                        .disabled(destination.isCurrent)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Move “\(item.lastPathComponent)”")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            let item = item, root = root
            destinations = await Task.detached {
                let parent = item.deletingLastPathComponent()
                let folders = [root] + AppFiles.allFolders(under: root, excluding: item)
                return folders.enumerated().map { index, url in
                    Destination(
                        url: url,
                        name: index == 0 ? "HTML Viewer" : url.lastPathComponent,
                        depth: index == 0 ? 0 : FolderScanner.relativePath(of: url, in: root).split(separator: "/").count,
                        isCurrent: AppFiles.isSameItem(url, parent)
                    )
                }
            }.value
        }
    }
}
