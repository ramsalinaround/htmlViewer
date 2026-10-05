import Compression
import CoreTransferable
import Foundation
import UniformTypeIdentifiers

enum ZipArchive {
    struct ZipError: LocalizedError {
        let errorDescription: String?
        init(_ message: String) { errorDescription = message }
    }

    /// Zips a folder into a new temporary file named `<folder>.zip`.
    ///
    /// Uses the system's built-in archiving: coordinated reads of a folder
    /// with `.forUploading` hand back a zip of it.
    static func archive(folder: URL) throws -> URL {
        var coordinationError: NSError?
        var result: Result<URL, Error> = .failure(ZipError("Couldn't create the archive."))
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &coordinationError) { zipURL in
            result = Result {
                let directory = FileManager.default.temporaryDirectory
                    .appending(path: "Archives/\(UUID().uuidString)", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appending(path: folder.lastPathComponent + ".zip")
                try FileManager.default.copyItem(at: zipURL, to: destination)
                return destination
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Extracts a standard zip file (stored or deflated entries) into `destination`.
    static func extract(_ zipURL: URL, to destination: URL) throws {
        let data = try Data(contentsOf: zipURL, options: .alwaysMapped)
        let reader = ByteReader(data: data)
        let fileManager = FileManager.default

        // The end-of-central-directory record sits within the last 64 KB + 22 bytes.
        guard data.count >= 22 else { throw ZipError("This isn't a valid zip file.") }
        var endRecord: Int?
        var offset = data.count - 22
        while offset >= max(0, data.count - 65_557) {
            if try reader.uint32(at: offset) == 0x0605_4B50 {
                endRecord = offset
                break
            }
            offset -= 1
        }
        guard let endRecord else { throw ZipError("This isn't a valid zip file.") }

        let entryCount = Int(try reader.uint16(at: endRecord + 10))
        var cursor = Int(try reader.uint32(at: endRecord + 16))
        if entryCount == 0xFFFF || cursor == 0xFFFF_FFFF {
            throw ZipError("Zip64 archives aren't supported.")
        }

        for _ in 0..<entryCount {
            guard try reader.uint32(at: cursor) == 0x0201_4B50 else {
                throw ZipError("The zip file is damaged.")
            }
            let flags = try reader.uint16(at: cursor + 8)
            let method = try reader.uint16(at: cursor + 10)
            let compressedSize = Int(try reader.uint32(at: cursor + 20))
            let uncompressedSize = Int(try reader.uint32(at: cursor + 24))
            let nameLength = Int(try reader.uint16(at: cursor + 28))
            let extraLength = Int(try reader.uint16(at: cursor + 30))
            let commentLength = Int(try reader.uint16(at: cursor + 32))
            let localHeader = Int(try reader.uint32(at: cursor + 42))
            let nameBytes = try reader.bytes(at: cursor + 46, count: nameLength)
            cursor += 46 + nameLength + extraLength + commentLength

            let isUTF8 = flags & 0x0800 != 0
            let rawName = (isUTF8 ? String(data: nameBytes, encoding: .utf8) : nil)
                ?? String(data: nameBytes, encoding: .utf8)
                ?? String(decoding: nameBytes, as: UTF8.self)
            let name = rawName.replacingOccurrences(of: "\\", with: "/")
            let components = name.split(separator: "/").map(String.init)

            // Skip macOS metadata and refuse paths that would escape the destination.
            if components.first == "__MACOSX" || components.last == ".DS_Store" || components.isEmpty { continue }
            guard !name.hasPrefix("/"), !components.contains("..") else {
                throw ZipError("The zip file contains an unsafe path: \(name)")
            }

            let target = components.reduce(destination) { $0.appending(path: $1) }
            if name.hasSuffix("/") {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            guard flags & 0x0001 == 0 else {
                throw ZipError("Password-protected zip files aren't supported.")
            }

            guard try reader.uint32(at: localHeader) == 0x0403_4B50 else {
                throw ZipError("The zip file is damaged.")
            }
            let localNameLength = Int(try reader.uint16(at: localHeader + 26))
            let localExtraLength = Int(try reader.uint16(at: localHeader + 28))
            let compressed = try reader.bytes(at: localHeader + 30 + localNameLength + localExtraLength, count: compressedSize)

            let contents: Data
            switch method {
            case 0:
                contents = compressed
            case 8:
                contents = try inflate(compressed, expectedSize: uncompressedSize)
            default:
                throw ZipError("\(name) uses an unsupported compression method.")
            }

            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: target)
        }
    }

    /// Decompresses raw DEFLATE data, which is what Compression calls ZLIB.
    private static func inflate(_ input: Data, expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        guard !input.isEmpty else { throw ZipError("The zip file is damaged.") }
        var output = Data(count: expectedSize)
        let written = output.withUnsafeMutableBytes { outputBuffer in
            input.withUnsafeBytes { inputBuffer in
                compression_decode_buffer(
                    outputBuffer.bindMemory(to: UInt8.self).baseAddress!, expectedSize,
                    inputBuffer.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == expectedSize else { throw ZipError("The zip file is damaged.") }
        return output
    }

    /// Bounds-checked little-endian reads.
    private struct ByteReader {
        let data: Data

        func bytes(at offset: Int, count: Int) throws -> Data {
            guard offset >= 0, count >= 0, offset + count <= data.count else {
                throw ZipError("The zip file is damaged.")
            }
            let start = data.startIndex + offset
            return data.subdata(in: start..<start + count)
        }

        func uint16(at offset: Int) throws -> UInt16 {
            let bytes = try bytes(at: offset, count: 2)
            return UInt16(bytes[bytes.startIndex]) | UInt16(bytes[bytes.startIndex + 1]) << 8
        }

        func uint32(at offset: Int) throws -> UInt32 {
            let bytes = try bytes(at: offset, count: 4)
            return (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[bytes.startIndex + $1]) << (8 * UInt32($1)) }
        }
    }
}

/// A folder shared as a .zip, built only when the user actually shares it.
struct FolderArchive: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            let url = archive.url
            let zip = try await Task.detached { try ZipArchive.archive(folder: url) }.value
            return SentTransferredFile(zip)
        }
    }
}
