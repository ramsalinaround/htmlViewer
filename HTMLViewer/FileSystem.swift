import Foundation

enum FileAccess {
    /// Reads a file through `NSFileCoordinator`, which makes iCloud Drive and
    /// other file providers download the file first if it isn't local yet.
    static func read(_ url: URL) throws -> Data {
        var coordinationError: NSError?
        var result: Result<Data, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { url in
            result = Result { try Data(contentsOf: url) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}

struct FolderListing: Sendable {
    var folders: [URL] = []
    var files: [URL] = []
}

enum FolderScanner {
    static let htmlExtensions: Set<String> = ["html", "htm", "xhtml", "xht", "shtml"]

    static func isHTML(_ url: URL) -> Bool {
        htmlExtensions.contains(url.pathExtension.lowercased())
    }

    /// Subfolders and HTML files directly inside `directory`.
    static func listing(of directory: URL) throws -> FolderListing {
        var listing = FolderListing()
        var coordinationError: NSError?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: directory, options: .withoutChanges, error: &coordinationError) { directory in
            do {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
                for item in contents {
                    guard let (url, isDirectory) = visibleItem(item) else { continue }
                    if isDirectory {
                        listing.folders.append(url)
                    } else if isHTML(url) {
                        listing.files.append(url)
                    }
                }
            } catch {
                readError = error
            }
        }
        if let error = coordinationError ?? readError { throw error }
        listing.folders.sort(by: byName)
        listing.files.sort(by: byName)
        return listing
    }

    /// Every HTML file anywhere under `root`, sorted by path.
    static func allHTMLFiles(under root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        var files: [URL] = []
        for case let item as URL in enumerator {
            guard let (url, isDirectory) = visibleItem(item) else {
                if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            if !isDirectory && isHTML(url) {
                files.append(url)
            }
        }
        return files.sorted {
            relativePath(of: $0, in: root).localizedStandardCompare(relativePath(of: $1, in: root)) == .orderedAscending
        }
    }

    /// The path of `url` below `root`, e.g. `docs/guide/index.html`.
    static func relativePath(of url: URL, in root: URL) -> String {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : url.lastPathComponent
    }

    /// Hides dot-files, but maps iCloud placeholders (`.page.html.icloud`)
    /// for files that aren't downloaded yet back to their real name.
    private static func visibleItem(_ item: URL) -> (URL, isDirectory: Bool)? {
        let name = item.lastPathComponent
        if name.hasPrefix(".") {
            guard name.hasSuffix(".icloud"), name.count > ".icloud".count + 1 else { return nil }
            let realName = String(name.dropFirst().dropLast(".icloud".count))
            return (item.deletingLastPathComponent().appending(path: realName), false)
        }
        let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return (item, isDirectory)
    }

    private static func byName(_ a: URL, _ b: URL) -> Bool {
        a.lastPathComponent.localizedStandardCompare(b.lastPathComponent) == .orderedAscending
    }
}
