import SwiftUI

@main
struct HTMLViewerApp: App {
    @State private var library = Library()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
        }
    }
}
