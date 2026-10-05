import Foundation

enum Route: Hashable {
    case folder(FolderRoute)
    case viewer(ViewerRoute)
}

struct FolderRoute: Hashable {
    /// The folder being shown.
    let url: URL
    /// The folder the user granted access to; pages may load anything inside it.
    let root: URL
    let title: String
}

struct ViewerRoute: Hashable {
    /// The files the viewer can step through with Previous / Next.
    let files: [URL]
    let index: Int
    let root: URL
    /// A web address to open instead, when `files` is empty.
    var startURL: URL? = nil
}

/// A file or folder, for `sheet(item:)` and similar.
struct FileItem: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
}
