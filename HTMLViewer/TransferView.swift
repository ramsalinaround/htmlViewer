import SwiftUI
import UIKit

@MainActor
@Observable
final class TransferModel {
    private(set) var state: TransferServer.State = .starting
    private(set) var addresses: [String] = []
    @ObservationIgnored private var server: TransferServer?

    func start(root: URL, onFilesChanged: @escaping @MainActor () -> Void) {
        guard server == nil else { return }
        addresses = NetworkAddresses.local()
        let server = TransferServer(
            root: root,
            onState: { [weak self] state in self?.state = state },
            onFilesChanged: onFilesChanged
        )
        self.server = server
        server.start()
    }

    func stop() {
        server?.stop()
        server = nil
    }

    /// Restarts after the app comes back from the background, where iOS
    /// may have shut the listener down.
    func refresh(root: URL, onFilesChanged: @escaping @MainActor () -> Void) {
        addresses = NetworkAddresses.local()
        if case .failed = state {
            stop()
            start(root: root, onFilesChanged: onFilesChanged)
        }
    }
}

struct TransferView: View {
    @Environment(Library.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TransferModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    status
                } header: {
                    Text("On your computer, open this address in a browser")
                } footer: {
                    Text("Your computer must be on the same Wi-Fi network as this device. Keep this screen open while transferring; the device won't go to sleep.")
                }

                Section("In the browser you can") {
                    Label("Upload files and whole folders. Drag and drop works too.", systemImage: "arrow.up.doc")
                    Label("Upload .zip files and have them unpacked into folders", systemImage: "doc.zipper")
                    Label("Download files, or whole folders as .zip", systemImage: "arrow.down.doc")
                    Label("Create and delete folders", systemImage: "folder.badge.plus")
                }

                Section {
                    Label("Anyone on the same network who knows the address can see and change the app's files while this screen is open.", systemImage: "lock.trianglebadge.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Wi-Fi Transfer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            model.start(root: library.documentsURL, onFilesChanged: library.filesDidChange)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            model.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                model.refresh(root: library.documentsURL, onFilesChanged: library.filesDidChange)
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .starting:
            HStack(spacing: 12) {
                ProgressView()
                Text("Starting…")
            }
        case .running(let port):
            if model.addresses.isEmpty {
                Label("Connect this device to Wi-Fi to use Wi-Fi Transfer.", systemImage: "wifi.slash")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.addresses, id: \.self) { address in
                    let url = port == 80 ? "http://\(address)" : "http://\(address):\(port)"
                    HStack {
                        Text(url)
                            .font(.title3.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Spacer()
                        Button("Copy", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = url
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn't start Wi-Fi Transfer", systemImage: "exclamationmark.triangle")
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    model.stop()
                    model.start(root: library.documentsURL, onFilesChanged: library.filesDidChange)
                }
            }
        }
    }
}
