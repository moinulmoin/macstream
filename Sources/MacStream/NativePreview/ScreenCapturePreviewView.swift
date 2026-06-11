import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import MacStreamCore
@preconcurrency import ScreenCaptureKit
import SwiftUI

struct ScreenCapturePreviewView: NSViewRepresentable {
    var configuration: PreviewCaptureConfiguration
    var captureTarget: ScreenCaptureTarget?

    func makeNSView(context: Context) -> ScreenCapturePreviewNSView {
        ScreenCapturePreviewNSView(configuration: configuration, captureTarget: captureTarget)
    }

    func updateNSView(_ nsView: ScreenCapturePreviewNSView, context: Context) {
        nsView.update(configuration: configuration, captureTarget: captureTarget)
    }

    static func dismantleNSView(_ nsView: ScreenCapturePreviewNSView, coordinator: ()) {
        nsView.stopCapture()
    }
}

final class ScreenCapturePreviewNSView: NSView {
    private let previewLayer = CALayer()
    private let controller = ScreenCapturePreviewController()

    init(configuration: PreviewCaptureConfiguration, captureTarget: ScreenCaptureTarget?) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        previewLayer.contentsGravity = .resizeAspectFill
        layer?.addSublayer(previewLayer)
        controller.update(configuration: configuration, captureTarget: captureTarget)

        controller.onFrame = { [weak self, weak controller] image in
            Task { @MainActor in
                self?.previewLayer.contents = image
                controller?.markFrameDelivered()
            }
        }
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(configuration: PreviewCaptureConfiguration, captureTarget: ScreenCaptureTarget?) {
        controller.update(configuration: configuration, captureTarget: captureTarget)
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopCapture()
        } else {
            controller.start()
        }
    }

    func stopCapture() {
        controller.stop()
    }
}

private final class ScreenCapturePreviewController: NSObject, SCStreamOutput, @unchecked Sendable {
    var onFrame: (@Sendable (CGImage) -> Void)?

    private let queue = DispatchQueue(label: "com.macstream.screen-preview.frames", qos: .userInitiated)
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var configuration = PreviewCaptureConfiguration()
    private var captureTarget: ScreenCaptureTarget?
    private var stream: SCStream?
    private var captureGeometry: PreviewCaptureGeometry?
    private var isStarting = false
    private var isRunning = false
    private var lastFrameTime = CFAbsoluteTimeGetCurrent()
    private var frameInterval = 1.0 / 12.0
    private var isFrameDeliveryPending = false

    func update(configuration: PreviewCaptureConfiguration, captureTarget: ScreenCaptureTarget?) {
        queue.async { [weak self] in
            guard let self else { return }
            let targetChanged = self.captureTarget != captureTarget
            guard self.configuration != configuration || targetChanged else { return }

            self.configuration = configuration
            self.captureTarget = captureTarget
            self.frameInterval = 1.0 / Double(configuration.framesPerSecond)

            guard let stream = self.stream else { return }
            guard targetChanged else {
                if let captureGeometry = self.captureGeometry {
                    let streamConfiguration = Self.streamConfiguration(
                        geometry: captureGeometry,
                        previewConfiguration: configuration
                    )
                    Task {
                        do {
                            try await stream.updateConfiguration(streamConfiguration)
                        } catch {
                            self.queue.async { [weak self] in
                                guard let self, self.stream === stream else { return }
                                self.restartCapture(using: stream)
                            }
                        }
                    }
                    return
                }

                self.restartCapture(using: stream)
                return
            }

            self.restartCapture(using: stream)
        }
    }

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            self.isRunning = true
            guard !self.isStarting, self.stream == nil else { return }
            self.isStarting = true

            Task {
                await self.startCapture()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            let stream = self.stream
            self.stream = nil
            self.captureGeometry = nil
            self.isStarting = false
            self.isRunning = false
            self.isFrameDeliveryPending = false

            Task {
                try? await stream?.stopCapture()
            }
        }
    }

    private func startCapture() async {
        let previewConfiguration = currentConfiguration()
        let captureTarget = currentCaptureTarget()

        guard CGPreflightScreenCaptureAccess() else {
            finishStartWithoutStream(configuration: previewConfiguration, captureTarget: captureTarget)
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let selection = Self.captureSelection(
                from: content,
                target: captureTarget
            ) else {
                finishStartWithoutStream(configuration: previewConfiguration, captureTarget: captureTarget)
                return
            }

            let configuration = Self.streamConfiguration(
                geometry: selection.geometry,
                previewConfiguration: previewConfiguration
            )

            let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()

            finishStart(
                with: stream,
                configuration: previewConfiguration,
                captureTarget: captureTarget,
                captureGeometry: selection.geometry
            )
        } catch {
            finishStartWithoutStream(configuration: previewConfiguration, captureTarget: captureTarget)
        }
    }

    private func finishStart(
        with stream: SCStream,
        configuration: PreviewCaptureConfiguration,
        captureTarget: ScreenCaptureTarget?,
        captureGeometry: PreviewCaptureGeometry
    ) {
        queue.async { [weak self] in
            guard let self else {
                Task { try? await stream.stopCapture() }
                return
            }

            self.isStarting = false
            guard self.isRunning,
                  self.configuration == configuration,
                  self.captureTarget == captureTarget
            else {
                Task { try? await stream.stopCapture() }
                if self.isRunning {
                    self.start()
                }
                return
            }

            self.stream = stream
            self.captureGeometry = captureGeometry
            self.isFrameDeliveryPending = false
        }
    }

    private func finishStartWithoutStream(
        configuration: PreviewCaptureConfiguration,
        captureTarget: ScreenCaptureTarget?
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            let shouldRestart = self.isRunning
                && (self.configuration != configuration || self.captureTarget != captureTarget)
            self.isStarting = false
            if shouldRestart {
                self.start()
            }
        }
    }

    private func currentConfiguration() -> PreviewCaptureConfiguration {
        queue.sync {
            configuration
        }
    }

    private func currentCaptureTarget() -> ScreenCaptureTarget? {
        queue.sync {
            captureTarget
        }
    }

    private func restartCapture(using stream: SCStream) {
        self.stream = nil
        self.captureGeometry = nil
        self.isFrameDeliveryPending = false

        Task {
            try? await stream.stopCapture()
            self.queue.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.start()
            }
        }
    }

    private static func streamConfiguration(
        geometry: PreviewCaptureGeometry,
        previewConfiguration: PreviewCaptureConfiguration
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = geometry.width(for: previewConfiguration.maxDisplayWidth)
        configuration.height = geometry.height(for: previewConfiguration.maxDisplayWidth)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(previewConfiguration.framesPerSecond))
        configuration.queueDepth = previewConfiguration.queueDepth
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        return configuration
    }

    private static func captureSelection(
        from content: SCShareableContent,
        target: ScreenCaptureTarget?
    ) -> ScreenCaptureSelection? {
        if target?.kind == .window,
           let window = content.windows.first(where: { "window-\($0.windowID)" == target?.id }) {
            let geometry = PreviewCaptureGeometry(
                sourceWidth: max(Int(window.frame.width.rounded()), 1),
                sourceHeight: max(Int(window.frame.height.rounded()), 1)
            )
            return ScreenCaptureSelection(
                filter: SCContentFilter(desktopIndependentWindow: window),
                geometry: geometry
            )
        }

        let display = content.displays.first { "display-\($0.displayID)" == target?.id } ?? content.displays.first
        guard let display else { return nil }

        let geometry = PreviewCaptureGeometry(
            sourceWidth: display.width,
            sourceHeight: display.height
        )
        return ScreenCaptureSelection(
            filter: SCContentFilter(display: display, excludingWindows: selfWindows(in: content)),
            geometry: geometry
        )
    }

    private static func selfWindows(in content: SCShareableContent) -> [SCWindow] {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return [] }
        return content.windows.filter { window in
            window.owningApplication?.bundleIdentifier == bundleIdentifier
        }
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard isRunning,
              self.stream === stream,
              outputType == .screen,
              sampleBuffer.isValid,
              let pixelBuffer = sampleBuffer.imageBuffer
        else {
            return
        }

        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastFrameTime >= frameInterval else { return }
        lastFrameTime = now

        guard !isFrameDeliveryPending, let onFrame else { return }

        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(image, from: image.extent) else {
            return
        }

        isFrameDeliveryPending = true
        onFrame(cgImage)
    }

    func markFrameDelivered() {
        queue.async { [weak self] in
            self?.isFrameDeliveryPending = false
        }
    }
}

private struct ScreenCaptureSelection {
    var filter: SCContentFilter
    var geometry: PreviewCaptureGeometry
}

private struct PreviewCaptureGeometry {
    var sourceWidth: Int
    var sourceHeight: Int

    init(sourceWidth: Int, sourceHeight: Int) {
        self.sourceWidth = max(1, sourceWidth)
        self.sourceHeight = max(1, sourceHeight)
    }

    func width(for maxDisplayWidth: Int) -> Int {
        min(sourceWidth, max(1, maxDisplayWidth))
    }

    func height(for maxDisplayWidth: Int) -> Int {
        max(1, Int(Double(width(for: maxDisplayWidth)) * Double(sourceHeight) / Double(sourceWidth)))
    }
}
