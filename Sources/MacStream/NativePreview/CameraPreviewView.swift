@preconcurrency import AVFoundation
import AppKit
import CoreImage
import MacStreamCore
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    var configuration = PreviewCaptureConfiguration()
    var cameraEnhancements = CameraEnhancementSettings()
    var cameraDeviceID: String?
    var onSetupFailure: (@MainActor (String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            configuration: configuration,
            cameraEnhancements: cameraEnhancements,
            cameraDeviceID: cameraDeviceID,
            onSetupFailure: onSetupFailure
        )
    }

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.update(cameraEnhancements: cameraEnhancements)
        view.previewLayer.session = context.coordinator.session
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.update(cameraEnhancements: cameraEnhancements)
        context.coordinator.update(configuration: configuration, cameraEnhancements: cameraEnhancements, cameraDeviceID: cameraDeviceID)
        if nsView.previewLayer.session !== context.coordinator.session {
            nsView.previewLayer.session = context.coordinator.session
        }
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.previewLayer.session = nil
    }

    final class Coordinator: @unchecked Sendable {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "com.macstream.camera-preview.session")
        private var isConfigured = false
        private var wantsRunning = false
        private var requestedPreset: AVCaptureSession.Preset
        private var requestedFramesPerSecond: Int
        private var requestedCameraEnhancements: CameraEnhancementSettings
        private var requestedDeviceID: String?
        private weak var videoDevice: AVCaptureDevice?
        private let onSetupFailure: (@MainActor (String) -> Void)?
        private var lastReportedSetupFailure: String?

        init(
            configuration: PreviewCaptureConfiguration,
            cameraEnhancements: CameraEnhancementSettings,
            cameraDeviceID: String?,
            onSetupFailure: (@MainActor (String) -> Void)?
        ) {
            self.requestedPreset = Self.sessionPreset(for: configuration)
            self.requestedFramesPerSecond = Self.frameRateLimit(for: configuration)
            self.requestedCameraEnhancements = cameraEnhancements
            self.requestedDeviceID = cameraDeviceID
            self.onSetupFailure = onSetupFailure
        }

        func start() {
            queue.async { [weak self] in
                self?.wantsRunning = true
            }

            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configureAndStart()
            case .notDetermined, .denied, .restricted:
                break
            @unknown default:
                break
            }
        }

        func update(configuration: PreviewCaptureConfiguration, cameraEnhancements: CameraEnhancementSettings, cameraDeviceID: String?) {
            let preset = Self.sessionPreset(for: configuration)
            let framesPerSecond = Self.frameRateLimit(for: configuration)

            queue.async { [weak self] in
                guard let self else { return }
                let shouldUpdateSession = self.requestedPreset != preset
                    || self.requestedFramesPerSecond != framesPerSecond
                let shouldUpdateCameraTuning = self.requestedCameraEnhancements != cameraEnhancements
                let shouldSwitchDevice = self.requestedDeviceID != cameraDeviceID
                guard shouldUpdateSession || shouldUpdateCameraTuning || shouldSwitchDevice else { return }

                self.requestedPreset = preset
                self.requestedFramesPerSecond = framesPerSecond
                self.requestedCameraEnhancements = cameraEnhancements
                self.requestedDeviceID = cameraDeviceID

                if self.wantsRunning, !self.isConfigured {
                    self.configureAndStartOnQueue()
                    return
                }

                guard self.isConfigured else { return }
                if shouldSwitchDevice {
                    self.reconfigureInput()
                }

                guard self.isConfigured else { return }

                if let videoDevice = self.videoDevice {
                    if shouldUpdateSession {
                        self.session.beginConfiguration()
                        self.applyRequestedPreset()
                        self.applyRequestedFrameRateLimit(to: videoDevice)
                        self.session.commitConfiguration()
                    }
                    if shouldUpdateCameraTuning {
                        self.applyRequestedCameraTuning(to: videoDevice)
                    }
                } else if shouldUpdateSession {
                    self.session.beginConfiguration()
                    self.applyRequestedPreset()
                    self.session.commitConfiguration()
                }

                if self.wantsRunning, !self.session.isRunning {
                    self.session.startRunning()
                }
            }
        }

        func stop() {
            queue.async { [weak self] in
                guard let self else { return }
                self.wantsRunning = false
                if self.session.isRunning {
                    self.session.stopRunning()
                }
            }
        }

        private func configureAndStart() {
            queue.async { [weak self] in
                self?.configureAndStartOnQueue()
            }
        }

        private func configureAndStartOnQueue() {
            guard wantsRunning else { return }

            if !isConfigured {
                session.beginConfiguration()
                applyRequestedPreset()
                defer { session.commitConfiguration() }

                guard configureInputOnQueue(failureDetail: "Camera preview input could not be created; the preview will retry when camera settings change.") else {
                    return
                }

                isConfigured = true
            }

            if wantsRunning, !session.isRunning {
                session.startRunning()
            }
        }

        private func reconfigureInput() {
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            for input in session.inputs {
                session.removeInput(input)
            }
            isConfigured = false
            guard configureInputOnQueue(failureDetail: "Camera preview input could not be reconfigured; the preview will retry when camera settings change.") else {
                return
            }
            isConfigured = true
        }

        private func configureInputOnQueue(failureDetail: String) -> Bool {
            guard let device = Self.resolveDevice(matching: requestedDeviceID),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input)
            else {
                videoDevice = nil
                reportSetupFailure(failureDetail)
                return false
            }
            session.addInput(input)
            videoDevice = device
            applyRequestedPreset()
            applyRequestedFrameRateLimit(to: device)
            applyRequestedCameraTuning(to: device)
            return true
        }

        private func reportSetupFailure(_ detail: String) {
            guard lastReportedSetupFailure != detail else { return }
            lastReportedSetupFailure = detail
            guard let onSetupFailure else { return }
            Task { @MainActor in
                onSetupFailure(detail)
            }
        }

        private static func resolveDevice(matching id: String?) -> AVCaptureDevice? {
            if let id {
                let discovery = AVCaptureDevice.DiscoverySession(
                    deviceTypes: [.builtInWideAngleCamera, .external],
                    mediaType: .video,
                    position: .unspecified
                )
                if let match = discovery.devices.first(where: { CaptureDeviceInfo.cameraID(uniqueID: $0.uniqueID) == id }) {
                    return match
                }
            }
            return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified)
                ?? AVCaptureDevice.default(for: .video)
        }

        private func applyRequestedPreset() {
            if session.sessionPreset != requestedPreset,
               session.canSetSessionPreset(requestedPreset) {
                session.sessionPreset = requestedPreset
            }
        }

        private func applyRequestedFrameRateLimit(to device: AVCaptureDevice) {
            guard let supportedFrameRate = Self.supportedFrameRate(
                nearest: requestedFramesPerSecond,
                for: device.activeFormat.videoSupportedFrameRateRanges
            ) else {
                return
            }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                let frameDuration = CMTime(value: 1, timescale: CMTimeScale(supportedFrameRate))
                device.activeVideoMinFrameDuration = frameDuration
                device.activeVideoMaxFrameDuration = frameDuration
            } catch {
                return
            }
        }

        private func applyRequestedCameraTuning(to device: AVCaptureDevice) {
            guard requestedCameraEnhancements.usesAutoLight else { return }

            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }

                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }

                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                    device.whiteBalanceMode = .continuousAutoWhiteBalance
                }
            } catch {
                return
            }
        }

        private static func sessionPreset(for configuration: PreviewCaptureConfiguration) -> AVCaptureSession.Preset {
            if configuration.framesPerSecond <= 8 || configuration.maxDisplayWidth <= 960 {
                return .medium
            }

            return .high
        }

        private static func frameRateLimit(for configuration: PreviewCaptureConfiguration) -> Int {
            configuration.framesPerSecond
        }

        private static func supportedFrameRate(
            nearest requestedFramesPerSecond: Int,
            for ranges: [AVFrameRateRange]
        ) -> Int? {
            let requested = Double(max(1, requestedFramesPerSecond))
            let candidate = ranges
                .map { range in
                    min(max(requested, range.minFrameRate), range.maxFrameRate)
                }
                .min { lhs, rhs in
                    let lhsDistance = abs(lhs - requested)
                    let rhsDistance = abs(rhs - requested)
                    if lhsDistance == rhsDistance {
                        return lhs < rhs
                    }
                    return lhsDistance < rhsDistance
                }

            guard let candidate else { return nil }
            return max(1, Int(candidate.rounded()))
        }
    }
}

final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private var cameraEnhancements = CameraEnhancementSettings()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        previewLayer.masksToBounds = true
        previewLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(cameraEnhancements: CameraEnhancementSettings) {
        guard self.cameraEnhancements != cameraEnhancements else { return }

        self.cameraEnhancements = cameraEnhancements
        applyPreviewFilters()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let layerSize = cameraEnhancements.rotation.isSideways
            ? CGSize(width: bounds.height, height: bounds.width)
            : bounds.size

        previewLayer.bounds = CGRect(origin: .zero, size: layerSize)
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        var transform = CGAffineTransform(rotationAngle: CGFloat(cameraEnhancements.rotation.radians))
        if cameraEnhancements.mirrorsPreview {
            transform = transform.scaledBy(x: -1, y: 1)
        }
        previewLayer.setAffineTransform(transform)
    }

    private func applyPreviewFilters() {
        guard cameraEnhancements.usesAutoLight,
              let filter = CIFilter(name: "CIColorControls")
        else {
            previewLayer.filters = nil
            return
        }

        filter.setDefaults()
        filter.setValue(cameraEnhancements.autoLightAmount * 0.18, forKey: kCIInputBrightnessKey)
        filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.08, forKey: kCIInputContrastKey)
        filter.setValue(1 + cameraEnhancements.autoLightAmount * 0.10, forKey: kCIInputSaturationKey)
        previewLayer.filters = [filter]
    }
}
