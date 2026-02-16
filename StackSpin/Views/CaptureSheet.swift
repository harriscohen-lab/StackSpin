import AVFoundation
import Combine
import SwiftUI
import UIKit

struct CaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cameraState: CameraAccessState = .checking
    var onCapture: (UIImage) -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch cameraState {
                case .authorized:
                    CameraPicker(sourceType: .camera) { image in
                        onCapture(image)
                        dismiss()
                    } onCancel: {
                        dismiss()
                    }
                    .ignoresSafeArea()
                case .checking:
                    ProgressView("Checking camera access…")
                case .unavailable:
                    PermissionMessage(
                        title: "Camera unavailable",
                        message: "This device does not have a camera available."
                    )
                case .denied:
                    PermissionMessage(
                        title: "Camera access denied",
                        message: "Enable camera access in Settings to capture album artwork.",
                        showSettingsButton: true
                    )
                }
            }
            .navigationTitle("Take Photo")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await refreshCameraAuthorization()
        }
    }

    @MainActor
    private func refreshCameraAuthorization() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraState = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraState = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraState = granted ? .authorized : .denied
        case .denied, .restricted:
            cameraState = .denied
        @unknown default:
            cameraState = .denied
        }
    }
}

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var cameraState: CameraAccessState = .checking
    var onScanned: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch cameraState {
                case .authorized:
                    BarcodeScannerView { code in
                        onScanned(code)
                        dismiss()
                    }
                    .ignoresSafeArea()
                case .checking:
                    ProgressView("Checking camera access…")
                case .unavailable:
                    PermissionMessage(
                        title: "Camera unavailable",
                        message: "This device does not have a camera available for barcode scanning."
                    )
                case .denied:
                    PermissionMessage(
                        title: "Scanner access denied",
                        message: "Enable camera access in Settings to scan UPC and EAN barcodes.",
                        showSettingsButton: true
                    )
                }
            }
            .navigationTitle("Scan Barcode")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            await refreshCameraAuthorization()
        }
    }

    @MainActor
    private func refreshCameraAuthorization() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraState = .unavailable
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            cameraState = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraState = granted ? .authorized : .denied
        case .denied, .restricted:
            cameraState = .denied
        @unknown default:
            cameraState = .denied
        }
    }
}

private enum CameraAccessState {
    case checking
    case authorized
    case denied
    case unavailable
}

private struct PermissionMessage: View {
    let title: String
    let message: String
    var showSettingsButton = false

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if showSettingsButton {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void = {}

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let controller = UIImagePickerController()
        controller.sourceType = sourceType
        controller.allowsEditing = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            guard let image = info[.originalImage] as? UIImage else { return }
            onCapture(image)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct BarcodeScannerView: UIViewRepresentable {
    @StateObject private var scanner = BarcodeScanner()
    var onScanned: (String) -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        let previewLayer = AVCaptureVideoPreviewLayer()
        scanner.configurePreview(layer: previewLayer)
        previewLayer.frame = UIScreen.main.bounds
        view.layer.addSublayer(previewLayer)

        context.coordinator.attach(scanner: scanner, onScanned: onScanned)
        scanner.start()
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.layer.sublayers?.first?.frame = uiView.bounds
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var cancellable: AnyCancellable?
        private weak var scanner: BarcodeScanner?

        func attach(scanner: BarcodeScanner, onScanned: @escaping (String) -> Void) {
            self.scanner = scanner
            cancellable = scanner.$detectedValue
                .compactMap { $0 }
                .removeDuplicates()
                .sink { code in
                    onScanned(code)
                }
        }

        func stop() {
            scanner?.stop()
            cancellable = nil
        }
    }
}
