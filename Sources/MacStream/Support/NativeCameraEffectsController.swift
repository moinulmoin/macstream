@preconcurrency import AVFoundation
import Combine
import Foundation
import MacStreamCore

@MainActor
final class NativeCameraEffectsController: ObservableObject {
    @Published private(set) var status = NativeCameraEffectsStatus.make(from: nil)

    private var selectedCameraDeviceID: String?

    func updateSelectedCameraDevice(id: String?) {
        selectedCameraDeviceID = id
        refresh()
    }

    func refresh() {
        guard let device = resolveSelectedCamera() else {
            status = NativeCameraEffectsStatus.make(from: nil)
            return
        }

        status = NativeCameraEffectsStatus.make(from: NativeCameraEffects.snapshot(for: device))
    }

    func openSystemVideoEffects() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }

    private func resolveSelectedCamera() -> AVCaptureDevice? {
        guard let selectedCameraDeviceID else {
            return nil
        }
        return SystemCaptureDeviceProvider.cameraDevice(
            matchingCaptureDeviceID: selectedCameraDeviceID
        )
    }
}
