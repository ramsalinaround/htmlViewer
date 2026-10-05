import SwiftUI
import UIKit

/// Shows the raw HTML of the document with selectable, monospaced text.
struct SourceView: View {
    let source: String
    let title: String

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SourceTextView(text: source)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = source
                        }
                    }
                }
        }
    }
}

/// `UITextView` copes with large files far better than SwiftUI `Text`,
/// and brings its own find bar (⌘F / long-press menu).
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
