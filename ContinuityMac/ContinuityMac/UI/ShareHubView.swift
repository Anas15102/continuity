import SwiftUI
import UniformTypeIdentifiers

/// Drag-and-drop file transfer zone embedded in the popover.
struct ShareHubView: View {
    @EnvironmentObject var fileTransfer: FileTransferEngine
    @State private var isDragTargeted = false
    @State private var transferMessage: String? = nil

    var body: some View {
        VStack(spacing: 8) {
            Text("Share Hub")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)

            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isDragTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1.5, dash: [6])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isDragTargeted
                                  ? Color.accentColor.opacity(0.08)
                                  : Color.secondary.opacity(0.05))
                    )
                    .frame(height: 90)

                if let message = transferMessage {
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(message.hasPrefix("✓") ? .green : .red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                } else if fileTransfer.isTransferring {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Sending \(fileTransfer.currentFileName ?? "file")...")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: isDragTargeted ? "arrow.down.circle.fill" : "arrow.down.to.line")
                            .font(.system(size: 22))
                            .foregroundStyle(isDragTargeted ? Color.accentColor : Color.secondary)
                        Text(isDragTargeted ? "Release to send" : "Drop files to send to phone")
                            .font(.system(size: 11))
                            .foregroundStyle(isDragTargeted ? Color.accentColor : Color.secondary)
                    }
                }
            }
            .padding(.horizontal, 16)
            // Use NSDraggingDestination via NSViewRepresentable wrapper for reliable drop
            .overlay(
                DropTargetView(isDragTargeted: $isDragTargeted) { urls in
                    handleDrop(urls: urls)
                }
            )
        }
        .padding(.vertical, 8)
    }

    // MARK: - Drop Handler

    private func handleDrop(urls: [URL]) {
        guard let url = urls.first else { return }
        fileTransfer.sendFile(at: url) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    transferMessage = "✓ Sent \(url.lastPathComponent)"
                case .failure(let error):
                    transferMessage = "✗ \(error.localizedDescription)"
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    transferMessage = nil
                }
            }
        }
    }
}

// MARK: - Native AppKit drop target (avoids popover dismissal on drag)

struct DropTargetView: NSViewRepresentable {
    @Binding var isDragTargeted: Bool
    var onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.isDragTargetedBinding = $isDragTargeted
        view.onDrop = onDrop
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.isDragTargetedBinding = $isDragTargeted
        nsView.onDrop = onDrop
    }

    class DropView: NSView {
        var isDragTargetedBinding: Binding<Bool>?
        var onDrop: (([URL]) -> Void)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.fileURL, .URL])
        }

        required init?(coder: NSCoder) { fatalError() }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            isDragTargetedBinding?.wrappedValue = true
            return .copy
        }

        override func draggingExited(_ sender: NSDraggingInfo?) {
            isDragTargetedBinding?.wrappedValue = false
        }

        override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
            return .copy
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            isDragTargetedBinding?.wrappedValue = false
            let pb = sender.draggingPasteboard
            guard let items = pb.readObjects(forClasses: [NSURL.self],
                                              options: [.urlReadingFileURLsOnly: true]) as? [URL],
                  !items.isEmpty else { return false }
            onDrop?(items)
            return true
        }
    }
}
