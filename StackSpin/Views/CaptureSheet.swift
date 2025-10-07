import SwiftUI
import UIKit

struct CaptureSheet: View {
    var onCapture: (UIImage) -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Capture not yet implemented")
                .foregroundStyle(.secondary)
            MonoButton(title: "Close") {
                // TODO(MVP): Hook up camera workflow
            }
        }
        .padding()
    }
}
