import SwiftUI

@main
struct HTMLViewerApp: App {
    var body: some Scene {
        DocumentGroup(viewing: HTMLDocument.self) { file in
            HTMLViewerScreen(data: file.document.data, fileURL: file.fileURL)
        }
    }
}
