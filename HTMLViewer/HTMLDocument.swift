import SwiftUI
import UniformTypeIdentifiers

/// A read-only HTML document. The app only views files, so writing just
/// hands back the original bytes.
struct HTMLDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.html] }

    var data: Data

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
