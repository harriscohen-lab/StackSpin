import AVFoundation
import Combine
import UIKit

final class BarcodeScanner: NSObject, ObservableObject {
    @Published var detectedValue: String?
    private let session = AVCaptureSession()
    private let output = AVCaptureMetadataOutput()

    func configurePreview(layer: AVCaptureVideoPreviewLayer) {
        layer.session = session
        layer.videoGravity = .resizeAspectFill
    }

    func start() {
        guard session.inputs.isEmpty else { session.startRunning(); return }
        guard let device = AVCaptureDevice.default(for: .video) else { return }
        do {
            let input = try AVCaptureDeviceInput(device: device)
            session.beginConfiguration()
            if session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
                output.metadataObjectTypes = [.ean13, .ean8, .upce, .code128]
                output.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            }
            session.commitConfiguration()
            session.startRunning()
        } catch {
            NSLog("Barcode scanner error: \(error)")
        }
    }

    func stop() {
        session.stopRunning()
    }
}

extension BarcodeScanner: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        detectedValue = value
    }
}
