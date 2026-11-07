import SwiftUI
import VisionKit

/// Point the camera at something written; the text it reads is highlighted, and tapping it
/// makes it the starting sentence. Uses Live Text (on-device), so it works offline.
struct TextScannerView: View {
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Live Text needs a camera and an A12 chip or later (not the simulator).
    @MainActor static var isAvailable: Bool {
        DataScannerViewController.isSupported
    }

    var body: some View {
        NavigationStack {
            Scanner { text in
                onPick(text)
                dismiss()
            }
            .ignoresSafeArea()
            .overlay(alignment: .bottom) {
                Text("Tap the highlighted text you want to anagram")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.bottom, 40)
            }
            .navigationTitle("Read a sentence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct Scanner: UIViewControllerRepresentable {
    let onPick: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPick: (String) -> Void
        init(onPick: @escaping (String) -> Void) { self.onPick = onPick }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            guard case .text(let text) = item else { return }
            let sentence = text.transcript
                .components(separatedBy: .newlines)
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !sentence.isEmpty else { return }
            onPick(sentence)
        }
    }
}
