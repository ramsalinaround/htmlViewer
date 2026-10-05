import XCTest
@testable import HTMLViewer

final class AppFilesTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testResolveStaysInsideRoot() {
        XCTAssertEqual(AppFiles.resolve(relativePath: "a/b.html", in: directory)?.lastPathComponent, "b.html")
        XCTAssertEqual(AppFiles.resolve(relativePath: "", in: directory), directory)
        XCTAssertNil(AppFiles.resolve(relativePath: "../outside", in: directory))
        XCTAssertNil(AppFiles.resolve(relativePath: "a/../../outside", in: directory))
    }

    func testUniqueNames() throws {
        try write("1", to: directory.appending(path: "page.html"))
        XCTAssertEqual(AppFiles.uniqueURL(for: "page.html", in: directory).lastPathComponent, "page 2.html")
        try write("2", to: directory.appending(path: "page 2.html"))
        XCTAssertEqual(AppFiles.uniqueURL(for: "page.html", in: directory).lastPathComponent, "page 3.html")
        XCTAssertEqual(AppFiles.uniqueURL(for: "new.html", in: directory).lastPathComponent, "new.html")
    }

    func testImportZipOfSingleFolderIsUnwrapped() throws {
        let zip = directory.appending(path: "Site.zip")
        try makeStoredZip([("Website/index.html", "<p>Hi</p>")]).write(to: zip)
        let documents = directory.appending(path: "Documents")

        let saved = try AppFiles.importItem(at: zip, into: documents, moveSource: true)

        XCTAssertEqual(saved.lastPathComponent, "Website")
        XCTAssertEqual(try read(saved.appending(path: "index.html")), "<p>Hi</p>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: zip.path), "moveSource should remove the zip")
    }

    func testImportZipOfLooseFilesUsesZipName() throws {
        let zip = directory.appending(path: "Pages.zip")
        try makeStoredZip([("a.html", "A"), ("b.html", "B")]).write(to: zip)
        let documents = directory.appending(path: "Documents")

        let saved = try AppFiles.importItem(at: zip, into: documents)

        XCTAssertEqual(saved.lastPathComponent, "Pages")
        XCTAssertEqual(try read(saved.appending(path: "b.html")), "B")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zip.path), "copying should keep the source")
    }

    func testImportFileDoesNotOverwrite() throws {
        let source = directory.appending(path: "in/page.html")
        try write("new", to: source)
        let documents = directory.appending(path: "Documents")
        try write("old", to: documents.appending(path: "page.html"))

        let saved = try AppFiles.importItem(at: source, into: documents)

        XCTAssertEqual(saved.lastPathComponent, "page 2.html")
        XCTAssertEqual(try read(documents.appending(path: "page.html")), "old")
    }

    func testCreateRenameMoveDelete() throws {
        let folder = try AppFiles.createFolder(named: "Docs", in: directory)
        XCTAssertThrowsError(try AppFiles.createFolder(named: "Docs", in: directory))
        XCTAssertThrowsError(try AppFiles.createFolder(named: "a/b", in: directory))

        let page = directory.appending(path: "page.html")
        try write("x", to: page)
        let renamed = try AppFiles.rename(page, to: "home.html")
        XCTAssertEqual(renamed.lastPathComponent, "home.html")
        XCTAssertFalse(FileManager.default.fileExists(atPath: page.path))

        let moved = try AppFiles.move(renamed, into: folder)
        XCTAssertTrue(AppFiles.isInside(moved, folder))
        XCTAssertEqual(try read(moved), "x")

        let child = try AppFiles.createFolder(named: "Child", in: folder)
        XCTAssertThrowsError(try AppFiles.move(folder, into: child), "a folder can't go inside itself")

        try AppFiles.delete(folder)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }
}
