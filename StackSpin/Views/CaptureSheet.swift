import SwiftUI
import UIKit

struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCapture: (UIImage) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Capture not yet implemented")
                .foregroundStyle(.secondary)
            MonoButton(title: "Close") {
                dismiss()
            }
        }
        .padding()
    }
}
