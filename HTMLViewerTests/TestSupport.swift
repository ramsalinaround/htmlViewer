import Foundation

/// A fresh temporary directory, removed when the test case tears down.
func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "HTMLViewerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

func read(_ url: URL) throws -> String {
    try String(decoding: Data(contentsOf: url), as: UTF8.self)
}

/// Builds a minimal zip with stored (uncompressed) entries, for crafting
/// archives the system zipper wouldn't produce.
func makeStoredZip(_ entries: [(name: String, contents: String)]) -> Data {
    func le16(_ value: Int) -> Data { withUnsafeBytes(of: UInt16(value).littleEndian) { Data($0) } }
    func le32(_ value: Int) -> Data { withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) } }

    var body = Data()
    var central = Data()
    for entry in entries {
        let name = Data(entry.name.utf8)
        let contents = Data(entry.contents.utf8)
        let offset = body.count
        body += le32(0x0403_4B50) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0)
        body += le32(0) + le32(contents.count) + le32(contents.count) + le16(name.count) + le16(0)
        body += name + contents
        central += le32(0x0201_4B50) + le16(20) + le16(20) + le16(0x0800) + le16(0) + le16(0) + le16(0)
        central += le32(0) + le32(contents.count) + le32(contents.count) + le16(name.count) + le16(0) + le16(0)
        central += le16(0) + le16(0) + le32(0) + le32(offset) + name
    }
    let end = le32(0x0605_4B50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count)
        + le32(central.count) + le32(body.count) + le16(0)
    return body + central + end
}
