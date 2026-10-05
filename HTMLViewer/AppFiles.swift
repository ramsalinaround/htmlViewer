import Foundation

/// File operations for the app's own folder (Documents).
enum AppFiles {
    struct FileError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Whether `url` is `directory` or somewhere inside it.
    static func isInside(_ url: URL, _ directory: URL) -> Bool {
        let path = normalizedPath(url)
        let directoryPath = normalizedPath(directory)
        return path == directoryPath || path.hasPrefix(directoryPath.hasSuffix("/") ? directoryPath : directoryPath + "/")
    }

    static func isSameItem(_ a: URL, _ b: URL) -> Bool {
        normalizedPath(a) == normalizedPath(b)
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    /// Turns a relative path like `site/css` into a URL inside `root`,
    /// refusing anything that would leave it.
    static func resolve(relativePath: String, in root: URL) -> URL? {
        let parts = relativePath.split(separator: "/").map(String.init).filter { !$0.isEmpty && $0 != "." }
        guard !parts.contains("..") else { return nil }
        return parts.reduce(root) { $0.appending(path: $1) }
    }

    /// `name`, or `name 2`, `name 3`… if something with that name exists.
    static func uniqueURL(for name: String, in directory: URL) -> URL {
        var candidate = directory.appending(path: name)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var number = 2
        repeat {
            candidate = directory.appending(path: ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)")
            number += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    /// Copies (or moves) a file or folder into `directory`. Zip files are
    /// unpacked into a folder. Returns the new item.
    @discardableResult
    static func importItem(at source: URL, into directory: URL, moveSource: Bool = false) throws -> URL {
        let didStartAccess = source.startAccessingSecurityScopedResource()
        defer { if didStartAccess { source.stopAccessingSecurityScopedResource() } }
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        if source.pathExtension.lowercased() == "zip" {
            let staging = fileManager.temporaryDirectory.appending(path: "Unzip/\(UUID().uuidString)", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: staging) }

            try FileAccess.coordinatedRead(source) { try ZipArchive.extract($0, to: staging) }

            // A zip of a single folder becomes that folder, not Folder/Folder.
            let items = try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            let content: URL
            let name: String
            if items.count == 1, isDirectory(items[0]) {
                content = items[0]
                name = items[0].lastPathComponent
            } else {
                content = staging
                name = source.deletingPathExtension().lastPathComponent
            }
            let destination = uniqueURL(for: name, in: directory)
            try fileManager.moveItem(at: content, to: destination)
            if moveSource { try? fileManager.removeItem(at: source) }
            return destination
        }

        let destination = uniqueURL(for: source.lastPathComponent, in: directory)
        if moveSource {
            try fileManager.moveItem(at: source, to: destination)
        } else {
            try FileAccess.coordinatedRead(source) { try fileManager.copyItem(at: $0, to: destination) }
        }
        return destination
    }

    @discardableResult
    static func createFolder(named name: String, in directory: URL) throws -> URL {
        let name = try validated(name)
        let url = directory.appending(path: name, directoryHint: .isDirectory)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            throw FileError("“\(name)” already exists.")
        }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func rename(_ url: URL, to newName: String) throws -> URL {
        let name = try validated(newName)
        guard name != url.lastPathComponent else { return url }
        let destination = url.deletingLastPathComponent().appending(path: name)
        // Allow case-only renames, which the file system sees as the same item.
        if FileManager.default.fileExists(atPath: destination.path),
           name.lowercased() != url.lastPathComponent.lowercased() {
            throw FileError("“\(name)” already exists.")
        }
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    @discardableResult
    static func move(_ url: URL, into directory: URL) throws -> URL {
        guard !isInside(directory, url) else {
            throw FileError("A folder can't be moved into itself.")
        }
        if isSameItem(url.deletingLastPathComponent(), directory) { return url }
        let destination = uniqueURL(for: url.lastPathComponent, in: directory)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    static func delete(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    static func removeIfEmpty(_ directory: URL) {
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: directory.path), contents.isEmpty {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    /// Every folder under `root`, sorted by path, leaving out `excluded` and its contents.
    static func allFolders(under root: URL, excluding excluded: URL? = nil) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var folders: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            if let excluded, isSameItem(url, excluded) {
                enumerator.skipDescendants()
                continue
            }
            folders.append(url)
        }
        return folders.sorted {
            FolderScanner.relativePath(of: $0, in: root)
                .localizedStandardCompare(FolderScanner.relativePath(of: $1, in: root)) == .orderedAscending
        }
    }

    private static func validated(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != ".." else { throw FileError("Please enter a name.") }
        guard !name.contains("/"), !name.contains(":") else { throw FileError("Names can't contain “/” or “:”.") }
        return name
    }

    /// Resolves `/private/var` vs `/var` and similar so paths compare reliably.
    private static func normalizedPath(_ url: URL) -> String {
        var path = url.resolvingSymlinksInPath().standardizedFileURL.path(percentEncoded: false)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
