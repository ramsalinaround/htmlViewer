import XCTest
@testable import HTMLViewer

/// Runs the Wi-Fi Transfer server for real and talks to it over HTTP.
@MainActor
final class TransferServerTests: XCTestCase {
    private var root: URL!
    private var server: TransferServer!
    private var baseURL: URL!
    private var changeCount = 0

    override func setUp() async throws {
        root = try makeTemporaryDirectory()
        let running = expectation(description: "server running")
        var port: UInt16 = 0
        server = TransferServer(
            root: root,
            onState: { state in
                if case .running(let p) = state, port == 0 {
                    port = p
                    running.fulfill()
                }
            },
            onFilesChanged: { [weak self] in self?.changeCount += 1 }
        )
        server.start()
        await fulfillment(of: [running], timeout: 10)
        baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }

    override func tearDown() async throws {
        server.stop()
        try? FileManager.default.removeItem(at: root)
    }

    private func request(_ method: String, _ path: String, query: [String: String] = [:], body: Data? = nil) async throws -> (Int, Data) {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, data)
    }

    private func listNames(_ path: String) async throws -> [String] {
        let (status, data) = try await request("GET", "/api/list", query: ["path": path])
        XCTAssertEqual(status, 200)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return (json["entries"] as! [[String: Any]]).map { $0["name"] as! String }
    }

    func testServesWebPage() async throws {
        let (status, data) = try await request("GET", "/")
        XCTAssertEqual(status, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Wi-Fi Transfer"))
    }

    func testUploadListDownloadDelete() async throws {
        let page = Data(("<h1>Hello</h1>" + String(repeating: "x", count: 3_000_000)).utf8)
        var (status, _) = try await request("PUT", "/api/upload", query: ["path": "My Site/pages/index.html"], body: page)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "My Site/pages/index.html")), page)
        XCTAssertGreaterThan(changeCount, 0)

        let names = try await listNames("My Site")
        XCTAssertEqual(names, ["pages"])

        let (downloadStatus, downloaded) = try await request("GET", "/api/download", query: ["path": "My Site/pages/index.html"])
        XCTAssertEqual(downloadStatus, 200)
        XCTAssertEqual(downloaded, page)

        // Uploading again replaces the file.
        (status, _) = try await request("PUT", "/api/upload", query: ["path": "My Site/pages/index.html"], body: Data("v2".utf8))
        XCTAssertEqual(status, 200)
        XCTAssertEqual(try read(root.appending(path: "My Site/pages/index.html")), "v2")

        (status, _) = try await request("POST", "/api/delete", query: ["path": "My Site"])
        XCTAssertEqual(status, 200)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "My Site").path))
    }

    func testUploadZipIsUnpacked() async throws {
        let zip = makeStoredZip([("Docs/index.html", "<p>Docs</p>")])
        let (status, _) = try await request("PUT", "/api/upload", query: ["path": "Docs.zip", "unzip": "1"], body: zip)
        XCTAssertEqual(status, 200)
        XCTAssertEqual(try read(root.appending(path: "Docs/index.html")), "<p>Docs</p>")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appending(path: "Docs.zip").path))
    }

    func testDownloadFolderAsZip() async throws {
        try write("<p>A</p>", to: root.appending(path: "Site/a.html"))
        let (status, data) = try await request("GET", "/api/download", query: ["path": "Site"])
        XCTAssertEqual(status, 200)

        let zip = root.appending(path: "downloaded.zip")
        try data.write(to: zip)
        let output = root.appending(path: "out")
        try ZipArchive.extract(zip, to: output)
        XCTAssertEqual(try read(output.appending(path: "Site/a.html")), "<p>A</p>")
    }

    func testMakeFolderAndEmptyUpload() async throws {
        var (status, _) = try await request("POST", "/api/mkdir", query: ["path": "New Folder"])
        XCTAssertEqual(status, 200)
        XCTAssertTrue(AppFiles.isDirectory(root.appending(path: "New Folder")))

        (status, _) = try await request("PUT", "/api/upload", query: ["path": "New Folder/empty.html"], body: Data())
        XCTAssertEqual(status, 200)
        XCTAssertEqual(try read(root.appending(path: "New Folder/empty.html")), "")
    }

    func testRejectsPathsOutsideRoot() async throws {
        var (status, _) = try await request("PUT", "/api/upload", query: ["path": "../escape.html"], body: Data("x".utf8))
        XCTAssertEqual(status, 400)
        (status, _) = try await request("GET", "/api/list", query: ["path": "../"])
        XCTAssertEqual(status, 400)
        (status, _) = try await request("POST", "/api/delete", query: ["path": ""])
        XCTAssertEqual(status, 400)
        (status, _) = try await request("GET", "/api/download", query: ["path": "missing.html"])
        XCTAssertEqual(status, 404)
        (status, _) = try await request("GET", "/nope")
        XCTAssertEqual(status, 404)
    }
}
