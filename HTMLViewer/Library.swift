import Foundation
import Observation

/// The folders the user has picked, remembered across launches with
/// security-scoped bookmarks.
@MainActor
@Observable
final class Library {
    struct Folder: Identifiable, Hashable {
        let id: UUID
        let name: String
        /// `nil` when the folder can no longer be found (deleted, provider signed out…).
        let url: URL?
    }

    private struct StoredFolder: Codable {
        var id: UUID
        var name: String
        var bookmark: Data
    }

    private(set) var folders: [Folder] = []

    /// Bumped whenever the app changes files, so open folder lists reload.
    private(set) var filesVersion = 0

    @ObservationIgnored private var stored: [StoredFolder] = []
    @ObservationIgnored private var accessedURLs: [UUID: URL] = [:]
    @ObservationIgnored private var accessedFiles: Set<URL> = []
    private let defaultsKey = "savedFolders"

    /// The app's own folder, shown in Files under On My iPhone › HTML Viewer.
    let documentsURL = URL.documentsDirectory

    init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([StoredFolder].self, from: data) {
            stored = decoded
        }
        folders = stored.indices.map { resolve(at: $0) }
        save()
    }

    /// Remembers a folder chosen in the folder picker and returns it.
    @discardableResult
    func addFolder(_ url: URL) throws -> Folder {
        let didStart = url.startAccessingSecurityScopedResource()
        let path = url.standardizedFileURL.path
        if let existing = folders.first(where: { $0.url?.standardizedFileURL.path == path }) {
            if didStart { url.stopAccessingSecurityScopedResource() }
            return existing
        }

        let bookmark: Data
        do {
            bookmark = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            if didStart { url.stopAccessingSecurityScopedResource() }
            throw error
        }

        let entry = StoredFolder(id: UUID(), name: url.lastPathComponent, bookmark: bookmark)
        if didStart { accessedURLs[entry.id] = url }
        stored.append(entry)
        let folder = Folder(id: entry.id, name: entry.name, url: url)
        folders.append(folder)
        save()
        return folder
    }

    func removeFolders(at offsets: IndexSet) {
        for index in offsets {
            if let url = accessedURLs.removeValue(forKey: stored[index].id) {
                url.stopAccessingSecurityScopedResource()
            }
        }
        stored.remove(atOffsets: offsets)
        folders.remove(atOffsets: offsets)
        save()
    }

    func moveFolders(from source: IndexSet, to destination: Int) {
        stored.move(fromOffsets: source, toOffset: destination)
        folders.move(fromOffsets: source, toOffset: destination)
        save()
    }

    func filesDidChange() {
        filesVersion += 1
    }

    /// Keeps access to a single file opened from the file picker or another app.
    func beginAccessing(file url: URL) {
        guard !accessedFiles.contains(url), url.startAccessingSecurityScopedResource() else { return }
        accessedFiles.insert(url)
    }

    private func resolve(at index: Int) -> Folder {
        let entry = stored[index]
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: entry.bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return Folder(id: entry.id, name: entry.name, url: nil)
        }

        if url.startAccessingSecurityScopedResource() {
            accessedURLs[entry.id] = url
        }
        if isStale, let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            stored[index].bookmark = fresh
        }
        return Folder(id: entry.id, name: entry.name, url: url)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(stored) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
