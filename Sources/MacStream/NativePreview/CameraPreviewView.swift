@preconcurrency import AVFoundation
import AppKit
import CoreImage
import MacStreamCore
import SwiftUI

struct CameraPreviewView: NSViewRepresentable {
    var configuration = PreviewCaptureConfiguration()
    var cameraEnhancements = CameraEnhancementSettings()
    var cameraDeviceID: String?
    var usesPresenterCutout = false
    var onSetupFailure: (@MainActor (String) -> Void)? = nil
    var onSourceSizeChange: (@MainActor (CGSize) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            configuration: configuration,
            cameraEnhancements: cameraEnhancements,
            cameraDeviceID: cameraDeviceID,
            usesPresenterCutout: usesPresenterCutout,
            onSetupFailure: onSetupFailure,
            onSourceSizeChange: onSourceSizeChange
        )
    }

    func makeNSView(context: Context) -> CameraPreviewNSView {
        let view = CameraPreviewNSView()
        view.update(
            cameraEnhancements: cameraEnhancements,
            usesPresenterCutout: usesPresenterCutout
        )
        context.coordinator.attach(view)
        view.previewLayer.session = usesPresenterCutout ? nil : context.coordinator.session
        context.coordinator.start()
        return view
    }

    func updateNSView(_ nsView: CameraPreviewNSView, context: Context) {
        nsView.update(
            cameraEnhancements: cameraEnhancements,
            usesPresenterCutout: usesPresenterCutout
        )
        context.coordinator.update(
            configuration: configuration,
            cameraEnhancements: cameraEnhancements,
            cameraDeviceID: cameraDeviceID,
            usesPresenterCutout: usesPresenterCutout
        )
        let previewSession = usesPresenterCutout ? nil : context.coordinator.session
        if nsView.previewLayer.session !== previewSession {
            nsView.previewLayer.session = previewSession
        }
    }

    static func dismantleNSView(_ nsView: CameraPreviewNSView, coordinator: Coordinator) {
        coordinator.stop()
        coordinator.detach(nsView)
        nsView.previewLayer.session = nil
    }

    final class Coordinator: @unchecked Sendable {
        let session = AVCaptureSession()
        private let queue = DispatchQueue(label: "com.macstream.camera-preview.session")
        private let cutoutOutputQueue = DispatchQueue(label: "com.macstream.camera-preview.cutout", qos: .userInitiated)
        private let handoffOwnerID = UUID()
        private let cutoutOutput = AVCaptureVideoDataOutput()
        private let cutoutFrameSink: CameraCutoutFrameSink
        private let cutoutFrameReceiver: CameraCutoutFrameReceiver
        private var isConfigured = false
        private var wantsRunning = false
        private var requestedPreset: AVCaptureSession.Preset
        private var requestedFramesPerSecond: Int
        private var requestedCameraEnhancements: CameraEnhancementSettings
        private var requestedDeviceID: String?
        private var requestedUsesPresenterCutout: Bool
        private weak var videoDevice: AVCaptureDevice?
        private let onSetupFailure: (@MainActor (String) -> Void)?
        private let onSourceSizeChange: (@MainActor (CGSize) -> Void)?
        private var lastReportedSetupFailure: String?

        init(
            configuration: PreviewCaptureConfiguration,
            cameraEnhancements: CameraEnhancementSettings,
            cameraDeviceID: String?,
            usesPresenterCutout: Bool,
            onSetupFailure: (@MainActor (String) -> Void)?,
            onSourceSizeChange: (@MainActor (CGSize) -> Void)?
        ) {
            let cutoutFrameSink = CameraCutoutFrameSink()
            self.requestedPreset = Self.sessionPreset(
                for: configuration,
                usesPresenterCutout: usesPresenterCutout
            )
            self.requestedFramesPerSecond = Self.frameRateLimit(
                for: configuration,
                usesPresenterCutout: usesPresenterCutout
            )
            self.requestedCameraEnhancements = cameraEnhancements
            self.requestedDeviceID = cameraDeviceID
            self.requestedUsesPresenterCutout = usesPresenterCutout
            self.onSetupFailure = onSetupFailure
            self.onSourceSizeChange = onSourceSizeChange
            self.cutoutFrameSink = cutoutFrameSink
            self.cutoutFrameReceiver = CameraCutoutFrameReceiver(
                sink: cutoutFrameSink,
                onSourceSizeChange: { size in
                    guard let onSourceSizeChange else { return }
                    Task { @MainActor in
                        onSourceSizeChange(size)
                    }
                }
            )
            self.cutoutFrameReceiver.update(cameraEnhancements: cameraEnhancements)
        }

        @MainActor
        func attach(_ view: CameraPreviewNSView) {
            cutoutFrameSink.attach(view)
        }

        @MainActor
        func detach(_ view: CameraPreviewNSView) {
            cutoutFrameSink.detach(view)
        }

        func start() {
            CameraCaptureHandoff.shared.claimIdlePreview(ownerID: handoffOwnerID)
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

        func update(
            configuration: PreviewCaptureConfiguration,
            cameraEnhancements: CameraEnhancementSettings,
            cameraDeviceID: String?,
            usesPresenterCutout: Bool
        ) {
            let preset = Self.sessionPreset(
                for: configuration,
                usesPresenterCutout: usesPresenterCutout
            )
            let framesPerSecond = Self.frameRateLimit(
                for: configuration,
                usesPresenterCutout: usesPresenterCutout
            )

            queue.async { [weak self] in
                guard let self else { return }
                let shouldUpdateSession = self.requestedPreset != preset
                    || self.requestedFramesPerSecond != framesPerSecond
                let shouldUpdateCameraTuning = self.requestedCameraEnhancements != cameraEnhancements
                let shouldSwitchDevice = self.requestedDeviceID != cameraDeviceID
                let shouldUpdateCutout = self.requestedUsesPresenterCutout != usesPresenterCutout
                guard shouldUpdateSession || shouldUpdateCameraTuning || shouldSwitchDevice || shouldUpdateCutout else { return }

                self.requestedPreset = preset
                self.requestedFramesPerSecond = framesPerSecond
                self.requestedCameraEnhancements = cameraEnhancements
                self.requestedDeviceID = cameraDeviceID
                self.requestedUsesPresenterCutout = usesPresenterCutout
                self.cutoutFrameReceiver.update(cameraEnhancements: cameraEnhancements)

                if self.wantsRunning, !self.isConfigured {
                    self.configureAndStartOnQueue()
                    return
                }

                guard self.isConfigured else { return }
                if shouldSwitchDevice {
                    self.reconfigureInput()
                }

                guard self.isConfigured else { return }

                if shouldUpdateCutout, !shouldSwitchDevice {
                    self.reconfigureCutoutOutput()
                }

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
                self.reportCurrentSourceSize()
            }
        }

        func stop() {
            queue.async { [self] in
                self.wantsRunning = false
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                self.cutoutOutput.setSampleBufferDelegate(nil, queue: nil)
                self.cutoutFrameReceiver.reset()
                CameraCaptureHandoff.shared.releaseIdlePreview(ownerID: self.handoffOwnerID)
            }
        }

        deinit {
            CameraCaptureHandoff.shared.releaseIdlePreview(ownerID: handoffOwnerID)
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
            reportCurrentSourceSize()
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
                cutoutFrameReceiver.reset()
                reportSetupFailure(failureDetail)
                return false
            }
            session.addInput(input)
            videoDevice = device
            applyRequestedPreset()
            applyRequestedFrameRateLimit(to: device)
            applyRequestedCameraTuning(to: device)
            configureCutoutOutputIfNeeded()
            return true
        }

        private func reconfigureCutoutOutput() {
            session.beginConfiguration()
            configureCutoutOutputIfNeeded()
            session.commitConfiguration()
        }

        private func configureCutoutOutputIfNeeded() {
            let isAttached = session.outputs.contains { $0 === cutoutOutput }
            guard requestedUsesPresenterCutout else {
                cutoutOutput.setSampleBufferDelegate(nil, queue: nil)
                if isAttached {
                    session.removeOutput(cutoutOutput)
                }
                cutoutFrameReceiver.setEnabled(false)
                return
            }

            cutoutFrameReceiver.setEnabled(true)
            guard !isAttached else { return }

            cutoutOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            cutoutOutput.alwaysDiscardsLateVideoFrames = true
            cutoutOutput.setSampleBufferDelegate(cutoutFrameReceiver, queue: cutoutOutputQueue)
            if session.canAddOutput(cutoutOutput) {
                session.addOutput(cutoutOutput)
            } else {
                cutoutOutput.setSampleBufferDelegate(nil, queue: nil)
                cutoutFrameReceiver.setEnabled(false)
                reportSetupFailure("Cutout preview could not attach to the selected camera.")
            }
        }

        private func reportSetupFailure(_ detail: String) {
            guard lastReportedSetupFailure != detail else { return }
            lastReportedSetupFailure = detail
            guard let onSetupFailure else { return }
            Task { @MainActor in
                onSetupFailure(detail)
            }
        }

        private func reportCurrentSourceSize() {
            guard let videoDevice, let onSourceSizeChange else { return }
            let dimensions = CMVideoFormatDescriptionGetDimensions(
                videoDevice.activeFormat.formatDescription
            )
            guard dimensions.width > 0, dimensions.height > 0 else { return }
            let size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
            Task { @MainActor in
                onSourceSizeChange(size)
            }
        }

        private static func resolveDevice(matching id: String?) -> AVCaptureDevice? {
            if let id,
               let match = SystemCaptureDeviceProvider.cameraDevice(matchingCaptureDeviceID: id) {
                return match
            }
            return SystemCaptureDeviceProvider.defaultCameraDevice()
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

        private static func sessionPreset(
            for configuration: PreviewCaptureConfiguration,
            usesPresenterCutout: Bool
        ) -> AVCaptureSession.Preset {
            if usesPresenterCutout {
                return .medium
            }
            if configuration.framesPerSecond <= 8 || configuration.maxDisplayWidth <= 960 {
                return .medium
            }

            return .high
        }

        private static func frameRateLimit(
            for configuration: PreviewCaptureConfiguration,
            usesPresenterCutout: Bool
        ) -> Int {
            usesPresenterCutout
                ? min(configuration.framesPerSecond, 10)
                : configuration.framesPerSecond
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

private final class CameraCutoutFrameReceiver: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private static let missingMatteGraceNanoseconds: UInt64 = 500_000_000
    private let lock = NSLock()
    private let segmentationProcessor = PresenterSegmentationProcessor(
        client: VisionPresenterSegmentationClient(quality: .balanced),
        maximumFramesPerSecond: 8
    )
    private let renderer = CameraCutoutPreviewRenderer()
    private let sink: CameraCutoutFrameSink
    private let onSourceSizeChange: @Sendable (CGSize) -> Void
    private var isEnabled = false
    private var cameraEnhancements = CameraEnhancementSettings()
    private var generation: UInt64 = 0
    private var lastSuccessfulFrameAtUptimeNanoseconds: UInt64?
    private var lastRenderedMatteAtUptimeNanoseconds: UInt64?
    private var hasDisplayedCutout = false
    private var lastSourceWidth = 0
    private var lastSourceHeight = 0

    init(
        sink: CameraCutoutFrameSink,
        onSourceSizeChange: @escaping @Sendable (CGSize) -> Void
    ) {
        self.sink = sink
        self.onSourceSizeChange = onSourceSizeChange
    }

    func setEnabled(_ isEnabled: Bool) {
        let didDisable = lock.withLock {
            guard self.isEnabled != isEnabled else { return false }
            let didDisable = self.isEnabled && !isEnabled
            self.isEnabled = isEnabled
            generation &+= 1
            lastSuccessfulFrameAtUptimeNanoseconds = nil
            lastRenderedMatteAtUptimeNanoseconds = nil
            hasDisplayedCutout = false
            return didDisable
        }
        if didDisable {
            segmentationProcessor.reset()
            sink.display(nil)
        }
    }

    func update(cameraEnhancements: CameraEnhancementSettings) {
        lock.withLock {
            self.cameraEnhancements = cameraEnhancements
        }
    }

    func reset() {
        lock.withLock {
            generation &+= 1
            lastSuccessfulFrameAtUptimeNanoseconds = nil
            lastRenderedMatteAtUptimeNanoseconds = nil
            hasDisplayedCutout = false
        }
        segmentationProcessor.reset()
        sink.display(nil)
    }

    nonisolated func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let state = lock.withLock {
            (
                isEnabled: isEnabled,
                cameraEnhancements: cameraEnhancements,
                generation: generation
            )
        }
        guard state.isEnabled,
              sampleBuffer.isValid,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            return
        }
        let sourceWidth = CVPixelBufferGetWidth(pixelBuffer)
        let sourceHeight = CVPixelBufferGetHeight(pixelBuffer)
        if sourceWidth != lastSourceWidth || sourceHeight != lastSourceHeight {
            lastSourceWidth = sourceWidth
            lastSourceHeight = sourceHeight
            onSourceSizeChange(CGSize(width: sourceWidth, height: sourceHeight))
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        segmentationProcessor.submit(pixelBuffer, presentationTime: presentationTime)
        guard let matte = segmentationProcessor.latestMatte(maximumAge: .milliseconds(500))
        else {
            clearAfterSustainedMatteFailure(for: state.generation)
            return
        }
        let shouldRender = lock.withLock {
            guard isEnabled,
                  generation == state.generation,
                  lastRenderedMatteAtUptimeNanoseconds != matte.processedAtUptimeNanoseconds
            else {
                return false
            }
            lastRenderedMatteAtUptimeNanoseconds = matte.processedAtUptimeNanoseconds
            return true
        }
        guard shouldRender,
              let image = renderer.makeImage(
                cameraPixelBuffer: matte.sourcePixelBuffer,
                mattePixelBuffer: matte.pixelBuffer,
                cameraEnhancements: state.cameraEnhancements
              )
        else {
            clearAfterSustainedMatteFailure(for: state.generation)
            return
        }
        let shouldDisplay = lock.withLock {
            guard isEnabled, generation == state.generation else { return false }
            lastSuccessfulFrameAtUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
            hasDisplayedCutout = true
            return true
        }
        guard shouldDisplay else { return }
        sink.display(image)
    }

    private func clearAfterSustainedMatteFailure(for expectedGeneration: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds
        let shouldClear = lock.withLock {
            guard isEnabled,
                  generation == expectedGeneration,
                  hasDisplayedCutout,
                  let lastSuccessfulFrameAtUptimeNanoseconds,
                  now >= lastSuccessfulFrameAtUptimeNanoseconds,
                  now - lastSuccessfulFrameAtUptimeNanoseconds >= Self.missingMatteGraceNanoseconds
            else {
                return false
            }
            hasDisplayedCutout = false
            return true
        }
        if shouldClear {
            sink.display(nil)
        }
    }
}

private final class CameraCutoutPreviewRenderer: @unchecked Sendable {
    private static let maximumOutputDimension: CGFloat = 320
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    func makeImage(
        cameraPixelBuffer: CVPixelBuffer,
        mattePixelBuffer: CVPixelBuffer,
        cameraEnhancements: CameraEnhancementSettings
    ) -> CGImage? {
        var cameraImage = CIImage(cvPixelBuffer: cameraPixelBuffer)
        let matteImage = CIImage(cvPixelBuffer: mattePixelBuffer)
        guard !cameraImage.extent.isEmpty, !matteImage.extent.isEmpty else { return nil }

        if cameraEnhancements.usesAutoLight {
            cameraImage = cameraImage.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: cameraEnhancements.autoLightAmount * 0.18,
                    kCIInputContrastKey: 1 + cameraEnhancements.autoLightAmount * 0.08,
                    kCIInputSaturationKey: 1 + cameraEnhancements.autoLightAmount * 0.10
                ]
            )
        }

        let normalizedCamera = cameraImage.transformed(by: CGAffineTransform(
            translationX: -cameraImage.extent.minX,
            y: -cameraImage.extent.minY
        ))
        let outputScale = min(
            1,
            Self.maximumOutputDimension / max(normalizedCamera.extent.width, normalizedCamera.extent.height)
        )
        cameraImage = normalizedCamera.transformed(by: CGAffineTransform(
            scaleX: outputScale,
            y: outputScale
        ))
        let normalizedMatte = matteImage.transformed(by: CGAffineTransform(
            translationX: -matteImage.extent.minX,
            y: -matteImage.extent.minY
        ))
        let alignedMatte = normalizedMatte
            .transformed(by: CGAffineTransform(
                scaleX: cameraImage.extent.width / matteImage.extent.width,
                y: cameraImage.extent.height / matteImage.extent.height
            ))
            .transformed(by: CGAffineTransform(
                translationX: cameraImage.extent.minX,
                y: cameraImage.extent.minY
            ))
            .cropped(to: cameraImage.extent)
        let transparentBackground = CIImage(color: .clear).cropped(to: cameraImage.extent)
        let cutout = cameraImage
            .applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: transparentBackground,
                    kCIInputMaskImageKey: alignedMatte
                ]
            )
            .cropped(to: cameraImage.extent)

        return context.createCGImage(
            cutout,
            from: cutout.extent,
            format: .RGBA8,
            colorSpace: colorSpace
        )
    }
}

private final class CameraCutoutFrameSink: @unchecked Sendable {
    private struct Frame: @unchecked Sendable {
        var image: CGImage?
    }

    private let lock = NSLock()
    private weak var view: CameraPreviewNSView?
    private var pendingFrame: Frame?
    private var isDeliveryScheduled = false

    @MainActor
    func attach(_ view: CameraPreviewNSView) {
        self.view = view
    }

    @MainActor
    func detach(_ view: CameraPreviewNSView) {
        if self.view === view {
            self.view = nil
        }
    }

    func display(_ image: CGImage?) {
        let frame = Frame(image: image)
        let shouldSchedule = lock.withLock {
            pendingFrame = frame
            guard !isDeliveryScheduled else { return false }
            isDeliveryScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        DispatchQueue.main.async { [weak self] in
            self?.deliverLatestFrame()
        }
    }

    @MainActor
    private func deliverLatestFrame() {
        let frame = lock.withLock {
            let frame = pendingFrame
            pendingFrame = nil
            isDeliveryScheduled = false
            return frame
        }
        view?.displayCutout(frame?.image)
    }
}

final class CameraPreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()
    private let cutoutLayer = CALayer()
    private var cameraEnhancements = CameraEnhancementSettings()
    private var usesPresenterCutout = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        previewLayer.masksToBounds = true
        previewLayer.videoGravity = .resizeAspectFill
        cutoutLayer.masksToBounds = true
        cutoutLayer.contentsGravity = .resizeAspectFill
        cutoutLayer.isOpaque = false
        cutoutLayer.isHidden = true
        layer?.addSublayer(previewLayer)
        layer?.addSublayer(cutoutLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        cameraEnhancements: CameraEnhancementSettings,
        usesPresenterCutout: Bool
    ) {
        let didChangeEnhancements = self.cameraEnhancements != cameraEnhancements
        let didChangeCutout = self.usesPresenterCutout != usesPresenterCutout
        guard didChangeEnhancements || didChangeCutout else { return }

        self.cameraEnhancements = cameraEnhancements
        self.usesPresenterCutout = usesPresenterCutout
        previewLayer.isHidden = usesPresenterCutout
        cutoutLayer.isHidden = !usesPresenterCutout
        if !usesPresenterCutout {
            cutoutLayer.contents = nil
        }
        if didChangeEnhancements {
            applyPreviewFilters()
        }
        needsLayout = true
    }

    func displayCutout(_ image: CGImage?) {
        guard usesPresenterCutout else { return }
        cutoutLayer.contents = image
    }

    override func layout() {
        super.layout()
        let layerSize = cameraEnhancements.rotation.isSideways
            ? CGSize(width: bounds.height, height: bounds.width)
            : bounds.size

        previewLayer.bounds = CGRect(origin: .zero, size: layerSize)
        previewLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        cutoutLayer.bounds = CGRect(origin: .zero, size: layerSize)
        cutoutLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)

        var transform = CGAffineTransform(rotationAngle: CGFloat(cameraEnhancements.rotation.radians))
        if cameraEnhancements.mirrorsPreview {
            transform = transform.scaledBy(x: -1, y: 1)
        }
        previewLayer.setAffineTransform(transform)
        cutoutLayer.setAffineTransform(transform)
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
