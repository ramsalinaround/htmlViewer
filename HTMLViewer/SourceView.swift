import SwiftUI
import UIKit

/// Shows the raw HTML of a file with selectable, monospaced text.
struct SourceView: View {
    let fileURL: URL

    @Environment(\.dismiss) private var dismiss
    @State private var source: String?

    var body: some View {
        NavigationStack {
            Group {
                if let source {
                    SourceTextView(text: source)
                        .ignoresSafeArea(edges: .bottom)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(fileURL.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = source
                    }
                    .disabled(source == nil)
                }
            }
        }
        .task {
            let url = fileURL
            source = await Task.detached {
                guard let data = try? FileAccess.read(url) else { return "Couldn't read \(url.lastPathComponent)." }
                return String(decoding: data, as: UTF8.self)
            }.value
        }
    }
}

/// `UITextView` copes with large files far better than SwiftUI `Text`,
/// and brings its own find bar.
private struct SourceTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.font = UIFontMetrics(forTextStyle: .body)
            .scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular))
        textView.adjustsFontForContentSizeCategory = true
        textView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        textView.isFindInteractionEnabled = true
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {}
}
