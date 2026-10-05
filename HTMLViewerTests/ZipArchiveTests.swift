import XCTest
@testable import HTMLViewer

final class ZipArchiveTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = try makeTemporaryDirectory()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testArchiveAndExtractRoundTrip() throws {
        let site = directory.appending(path: "My Site")
        let page = "<html><body>" + String(repeating: "Hello, world! ", count: 2_000) + "</body></html>"
        try write(page, to: site.appending(path: "index.html"))
        try write("body { color: red }", to: site.appending(path: "css/style.css"))
        try write("<p>Café ☕️</p>", to: site.appending(path: "Pagès/über.html"))
        try write("", to: site.appending(path: "empty.txt"))

        let zip = try ZipArchive.archive(folder: site)
        XCTAssertEqual(zip.lastPathComponent, "My Site.zip")

        let output = directory.appending(path: "out")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try ZipArchive.extract(zip, to: output)

        let extracted = output.appending(path: "My Site")
        XCTAssertEqual(try read(extracted.appending(path: "index.html")), page)
        XCTAssertEqual(try read(extracted.appending(path: "css/style.css")), "body { color: red }")
        XCTAssertEqual(try read(extracted.appending(path: "Pagès/über.html")), "<p>Café ☕️</p>")
        XCTAssertEqual(try read(extracted.appending(path: "empty.txt")), "")
    }

    func testExtractStoredEntriesAndSkipsMacMetadata() throws {
        let zip = directory.appending(path: "stored.zip")
        try makeStoredZip([
            ("docs/", ""),
            ("docs/a.html", "<p>A</p>"),
            ("__MACOSX/docs/._a.html", "junk"),
            ("docs/.DS_Store", "junk"),
        ]).write(to: zip)

        let output = directory.appending(path: "out")
        try ZipArchive.extract(zip, to: output)

        XCTAssertEqual(try read(output.appending(path: "docs/a.html")), "<p>A</p>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appending(path: "__MACOSX").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.appending(path: "docs/.DS_Store").path))
    }

    func testExtractRejectsPathTraversal() throws {
        let zip = directory.appending(path: "evil.zip")
        try makeStoredZip([("../evil.html", "nope")]).write(to: zip)

        let output = directory.appending(path: "out")
        XCTAssertThrowsError(try ZipArchive.extract(zip, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appending(path: "evil.html").path))
    }

    func testExtractRejectsGarbage() throws {
        let file = directory.appending(path: "not-a.zip")
        try Data("definitely not a zip file".utf8).write(to: file)
        XCTAssertThrowsError(try ZipArchive.extract(file, to: directory.appending(path: "out")))
    }
}
