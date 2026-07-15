@preconcurrency import AppKit
@preconcurrency import AVFoundation
import AudioToolbox
import CoreGraphics
@preconcurrency import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public protocol SignalProvider: Sendable {
    func update(configuration: SignalSamplingConfiguration)
    func start()
    func stop()
    func snapshot() -> SignalSnapshot
}

public extension SignalProvider {
    func update(configuration: SignalSamplingConfiguration) {}
}

public final class PreviewSignalProvider: SignalProvider, @unchecked Sendable {
    private var generator = DemoSignalGenerator()

    public init() {}

    public func start() {}

    public func stop() {}

    public func snapshot() -> SignalSnapshot {
        generator.next()
    }
}

public final class SystemSignalProvider: SignalProvider, @unchecked Sendable {
    private let microphone = MicrophoneLevelMonitor()
    private let screenMotion = ScreenMotionMonitor()
    private let stateQueue = DispatchQueue(label: "com.ideaplexa.macstream.signal-provider")
    private var configuration = SignalSamplingConfiguration()
    private var isStarted = false

    public init() {}

    public func update(configuration: SignalSamplingConfiguration) {
        stateQueue.async {
            self.configuration = configuration
            self.applyMonitorsForCurrentState(configuration: configuration)
        }
    }

    public func start() {
        stateQueue.async {
            self.isStarted = true
            self.applyMonitorsForCurrentState(configuration: self.configuration)
        }
    }

    public func stop() {
        stateQueue.async {
            self.isStarted = false
            self.microphone.stop()
            self.screenMotion.stop()
        }
    }

    public func snapshot() -> SignalSnapshot {
        let configuration = currentConfiguration()
        let microphoneSnapshot = configuration.isMicrophoneEnabled
            ? microphone.snapshot()
            : MicrophoneSnapshot(level: 0, isSpeaking: false, isUnavailable: true)
        let screenSnapshot = configuration.isScreenMotionEnabled
            ? screenMotion.snapshot()
            : ScreenMotionSnapshot(motion: 0, isFrozen: false, isUnavailable: true)
        let activityContext = configuration.isActivityContextEnabled
            ? Self.activityContextSnapshot()
            : (activeApplication: "Source monitor", idleSeconds: 0)

        return SignalSnapshot(
            isSpeaking: microphoneSnapshot.isSpeaking,
            speechLevel: microphoneSnapshot.level,
            screenMotion: screenSnapshot.motion,
            hasFace: true,
            activeApplication: activityContext.activeApplication,
            idleSeconds: activityContext.idleSeconds,
            isScreenFrozen: screenSnapshot.isFrozen,
            isMicMuted: microphoneSnapshot.isUnavailable
        )
    }

    private static func activityContextSnapshot() -> (activeApplication: String, idleSeconds: Double) {
        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .mouseMoved)
        let keyboardIdle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: .keyDown)
        let activeApplication = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"

        return (activeApplication, min(idleSeconds, keyboardIdle))
    }

    private func currentConfiguration() -> SignalSamplingConfiguration {
        stateQueue.sync {
            configuration
        }
    }

    private func applyMonitorsForCurrentState(configuration: SignalSamplingConfiguration) {
        guard isStarted else {
            screenMotion.update(configuration: configuration)
            return
        }

        if configuration.isMicrophoneEnabled {
            microphone.start(deviceID: configuration.microphoneDeviceID)
        } else {
            microphone.stop()
        }

        screenMotion.update(configuration: configuration)
        if configuration.isScreenMotionEnabled {
            screenMotion.start()
        } else {
            screenMotion.stop()
        }
    }
}

private struct MicrophoneSnapshot: Sendable {
    var level: Double
    var isSpeaking: Bool
    var isUnavailable: Bool
}

private struct ScreenMotionSnapshot: Sendable {
    var motion: Double
    var isFrozen: Bool
    var isUnavailable: Bool
}

struct AudioLevelMeasurement: Equatable, Sendable {
    var level: Double
    var isSpeaking: Bool
}

struct AudioLevelMeterState: Equatable, Sendable {
    private(set) var measurement = AudioLevelMeasurement(level: 0, isSpeaking: false)

    mutating func record(normalizedLevel: Double) -> AudioLevelMeasurement {
        let normalizedLevel = min(max(normalizedLevel, 0), 1)
        measurement.level = (measurement.level * 0.7) + (normalizedLevel * 0.3)
        measurement.isSpeaking = normalizedLevel > 0.18
        return measurement
    }

    mutating func reset() {
        measurement = AudioLevelMeasurement(level: 0, isSpeaking: false)
    }
}

final class ReusableAudioLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var state = AudioLevelMeterState()
    private var audioDataScratch: UnsafeMutableRawPointer?
    private var audioDataScratchCapacity = 0

    deinit {
        audioDataScratch?.deallocate()
    }

    func measure(_ sampleBuffer: CMSampleBuffer) -> AudioLevelMeasurement? {
        lock.lock()
        defer { lock.unlock() }
        guard let normalizedLevel = normalizedLevel(from: sampleBuffer) else { return nil }
        return state.record(normalizedLevel: normalizedLevel)
    }

    func reset() {
        lock.lock()
        state.reset()
        lock.unlock()
    }

    private func normalizedLevel(from sampleBuffer: CMSampleBuffer) -> Double? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              streamDescription.pointee.mFormatID == kAudioFormatLinearPCM else {
            return nil
        }

        let bitsPerChannel = Int(streamDescription.pointee.mBitsPerChannel)
        guard bitsPerChannel > 0 else { return nil }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer),
              let audioData = audioDataPointer(from: blockBuffer)
        else {
            return nil
        }

        return withExtendedLifetime(blockBuffer) {
            let flags = streamDescription.pointee.mFormatFlags
            let isFloat = flags & kAudioFormatFlagIsFloat != 0
            let isSignedInteger = flags & kAudioFormatFlagIsSignedInteger != 0
            var sumSquares = 0.0
            var sampleCount = 0

            if isFloat, bitsPerChannel == 32 {
                let samples = audioData.pointer.bindMemory(
                    to: Float.self,
                    capacity: audioData.byteCount / MemoryLayout<Float>.stride
                )
                for index in 0..<(audioData.byteCount / MemoryLayout<Float>.stride) {
                    let sample = Double(samples[index])
                    sumSquares += sample * sample
                    sampleCount += 1
                }
            } else if isSignedInteger, bitsPerChannel == 16 {
                let samples = audioData.pointer.bindMemory(
                    to: Int16.self,
                    capacity: audioData.byteCount / MemoryLayout<Int16>.stride
                )
                for index in 0..<(audioData.byteCount / MemoryLayout<Int16>.stride) {
                    let sample = Double(samples[index]) / Double(Int16.max)
                    sumSquares += sample * sample
                    sampleCount += 1
                }
            } else if isSignedInteger, bitsPerChannel == 32 {
                let samples = audioData.pointer.bindMemory(
                    to: Int32.self,
                    capacity: audioData.byteCount / MemoryLayout<Int32>.stride
                )
                for index in 0..<(audioData.byteCount / MemoryLayout<Int32>.stride) {
                    let sample = Double(samples[index]) / Double(Int32.max)
                    sumSquares += sample * sample
                    sampleCount += 1
                }
            } else {
                return nil
            }

            guard sampleCount > 0 else { return nil }
            let meanSquare = sumSquares / Double(sampleCount)
            guard meanSquare > 0 else { return 0 }

            let rms = sqrt(meanSquare)
            let decibels = 20 * log10(max(rms, 0.000_001))
            return min(max((decibels + 60) / 60, 0), 1)
        }
    }

    private func audioDataPointer(
        from blockBuffer: CMBlockBuffer
    ) -> (pointer: UnsafeRawPointer, byteCount: Int)? {
        var lengthAtOffset = 0
        var totalLength = 0
        var contiguousPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &contiguousPointer
        )
        if status == kCMBlockBufferNoErr,
           lengthAtOffset == totalLength,
           let contiguousPointer,
           totalLength > 0 {
            return (UnsafeRawPointer(contiguousPointer), totalLength)
        }

        let byteCount = CMBlockBufferGetDataLength(blockBuffer)
        guard byteCount > 0 else { return nil }
        ensureAudioDataScratchCapacity(byteCount)
        guard let audioDataScratch,
              CMBlockBufferCopyDataBytes(
                  blockBuffer,
                  atOffset: 0,
                  dataLength: byteCount,
                  destination: audioDataScratch
              ) == kCMBlockBufferNoErr
        else {
            return nil
        }
        return (UnsafeRawPointer(audioDataScratch), byteCount)
    }

    private func ensureAudioDataScratchCapacity(_ requiredCapacity: Int) {
        guard requiredCapacity > audioDataScratchCapacity else { return }
        audioDataScratch?.deallocate()
        audioDataScratch = UnsafeMutableRawPointer.allocate(
            byteCount: requiredCapacity,
            alignment: 16
        )
        audioDataScratchCapacity = requiredCapacity
    }
}

private final class MicrophoneLevelMonitor: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let sessionQueue = DispatchQueue(label: "com.macstream.signal.microphone-session", qos: .utility)
    private let sampleQueue = DispatchQueue(label: "com.macstream.signal.microphone-samples", qos: .userInitiated)
    private let levelMeter = ReusableAudioLevelMeter()
    private let lock = NSLock()
    private var level: Double = 0
    private var isSpeaking = false
    private var isUnavailable = false
    private var activeOutputIdentifier: ObjectIdentifier?
    private var isStartRequested = false
    private var isPermissionRequestInFlight = false
    private var requestedDeviceID: String?
    private var activeDeviceID: String?
    private var session: AVCaptureSession?
    private var output: AVCaptureAudioDataOutput?

    func start(deviceID: String?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.isStartRequested = true
            self.requestedDeviceID = deviceID
            self.startCaptureIfPossible()
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.isStartRequested = false
            self.stopSession()
        }
    }

    func snapshot() -> MicrophoneSnapshot {
        lock.lock()
        defer { lock.unlock() }

        return MicrophoneSnapshot(level: level, isSpeaking: isSpeaking, isUnavailable: isUnavailable)
    }

    private func startCaptureIfPossible() {
        guard isStartRequested else {
            stopSession()
            return
        }

        guard let deviceID = requestedDeviceID else {
            stopSession()
            update(level: 0, isSpeaking: false, isUnavailable: true)
            return
        }

        if session != nil, activeDeviceID == deviceID {
            let snapshot = snapshot()
            update(level: snapshot.level, isSpeaking: snapshot.isSpeaking, isUnavailable: false)
            return
        }

        guard let device = Self.device(matching: deviceID) else {
            stopSession()
            update(level: 0, isSpeaking: false, isUnavailable: true)
            return
        }

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            configureAndStartSession(device: device, deviceID: deviceID)
        case .notDetermined:
            requestPermissionIfNeeded()
        case .denied, .restricted:
            stopSession()
            update(level: 0, isSpeaking: false, isUnavailable: true)
        @unknown default:
            stopSession()
            update(level: 0, isSpeaking: false, isUnavailable: true)
        }
    }

    private func requestPermissionIfNeeded() {
        guard !isPermissionRequestInFlight else { return }
        isPermissionRequestInFlight = true

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            guard let self else { return }
            self.sessionQueue.async {
                self.isPermissionRequestInFlight = false
                if MicrophonePermissionStartPolicy.shouldStartCapture(
                    isStartRequested: self.isStartRequested,
                    isPermissionGranted: granted
                ) {
                    self.startCaptureIfPossible()
                } else {
                    self.stopSession()
                    self.update(level: 0, isSpeaking: false, isUnavailable: true)
                }
            }
        }
    }

    private func configureAndStartSession(device: AVCaptureDevice, deviceID: String) {
        stopSession()

        do {
            let nextSession = AVCaptureSession()
            nextSession.beginConfiguration()

            let input = try AVCaptureDeviceInput(device: device)
            guard nextSession.canAddInput(input) else {
                nextSession.commitConfiguration()
                update(level: 0, isSpeaking: false, isUnavailable: true)
                return
            }
            nextSession.addInput(input)

            let nextOutput = AVCaptureAudioDataOutput()
            nextOutput.setSampleBufferDelegate(self, queue: sampleQueue)
            guard nextSession.canAddOutput(nextOutput) else {
                nextOutput.setSampleBufferDelegate(nil, queue: nil)
                nextSession.commitConfiguration()
                update(level: 0, isSpeaking: false, isUnavailable: true)
                return
            }
            nextSession.addOutput(nextOutput)
            nextSession.commitConfiguration()

            session = nextSession
            output = nextOutput
            activeDeviceID = deviceID
            setActiveOutput(nextOutput)
            update(level: 0, isSpeaking: false, isUnavailable: false)

            nextSession.startRunning()
            if !shouldContinueStartingCapture() || requestedDeviceID != deviceID {
                stopSession()
            }
        } catch {
            update(level: 0, isSpeaking: false, isUnavailable: true)
        }
    }

    private func shouldContinueStartingCapture() -> Bool {
        isStartRequested
    }

    private func stopSession() {
        setActiveOutput(nil)
        output?.setSampleBufferDelegate(nil, queue: nil)
        if session?.isRunning == true {
            session?.stopRunning()
        }
        output = nil
        session = nil
        activeDeviceID = nil
        levelMeter.reset()
        update(level: 0, isSpeaking: false, isUnavailable: true)
    }

    private static func device(matching id: String) -> AVCaptureDevice? {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        )

        return discovery.devices.first {
            CaptureDeviceInfo.microphoneID(uniqueID: $0.uniqueID) == id || $0.uniqueID == id
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard isActiveOutput(output) else { return }
        guard let measurement = levelMeter.measure(sampleBuffer) else { return }
        update(
            level: measurement.level,
            isSpeaking: measurement.isSpeaking,
            isUnavailable: false,
            from: output
        )
    }

    private func isActiveOutput(_ output: AVCaptureOutput) -> Bool {
        lock.withLock {
            activeOutputIdentifier == ObjectIdentifier(output)
        }
    }

    private func setActiveOutput(_ output: AVCaptureOutput?) {
        lock.withLock {
            activeOutputIdentifier = output.map(ObjectIdentifier.init)
        }
    }

    private func update(
        level: Double,
        isSpeaking: Bool,
        isUnavailable: Bool,
        from output: AVCaptureOutput
    ) {
        lock.lock()
        defer { lock.unlock() }
        guard activeOutputIdentifier == ObjectIdentifier(output) else { return }

        self.level = min(max(level, 0), 1)
        self.isSpeaking = isSpeaking
        self.isUnavailable = isUnavailable
    }

    private func update(level: Double, isSpeaking: Bool, isUnavailable: Bool) {
        lock.lock()
        self.level = min(max(level, 0), 1)
        self.isSpeaking = isSpeaking
        self.isUnavailable = isUnavailable
        lock.unlock()
    }
}

struct MicrophonePermissionStartPolicy: Sendable {
    static func shouldStartCapture(isStartRequested: Bool, isPermissionGranted: Bool) -> Bool {
        isStartRequested && isPermissionGranted
    }
}

struct ScreenMotionFrameSamplingGate: Sendable {
    static func shouldSample(now: Double, lastSampleTime: Double?, interval: Double) -> Bool {
        guard let lastSampleTime else { return true }
        return now - lastSampleTime >= max(interval, 0)
    }
}

struct ScreenMotionLumaSamplingGrid: Sendable {
    static let columns = 16
    static let rows = 9

    static var capacity: Int {
        columns * rows
    }
}

private struct DemoSignalGenerator: Sendable {
    private var step = 0

    mutating func next() -> SignalSnapshot {
        step += 1
        let phase = step % 36

        switch phase {
        case 0...5:
            return SignalSnapshot(isSpeaking: true, speechLevel: 0.72, screenMotion: 0.12, hasFace: true, activeApplication: "Notes", idleSeconds: 0)
        case 6...15:
            return SignalSnapshot(isSpeaking: true, speechLevel: 0.62, screenMotion: 0.67, hasFace: true, activeApplication: "Xcode", idleSeconds: 0)
        case 16...24:
            return SignalSnapshot(isSpeaking: false, speechLevel: 0.08, screenMotion: 0.74, hasFace: true, activeApplication: "Simulator", idleSeconds: 4)
        case 25...31:
            return SignalSnapshot(isSpeaking: false, speechLevel: 0.02, screenMotion: 0.05, hasFace: true, activeApplication: "Finder", idleSeconds: 44)
        case 32:
            return SignalSnapshot(isSpeaking: true, speechLevel: 0.61, screenMotion: 0.11, hasFace: true, activeApplication: "Notes", idleSeconds: 0, isMicMuted: true)
        default:
            return SignalSnapshot(isSpeaking: false, speechLevel: 0.04, screenMotion: 0.03, hasFace: true, activeApplication: "Safari", idleSeconds: 8, isScreenFrozen: phase == 34)
        }
    }
}

private final class ScreenMotionMonitor: NSObject, SCStreamOutput, @unchecked Sendable {
    private static let maxCaptureWidth = 320
    private let queue = DispatchQueue(label: "com.macstream.signal.screen-motion", qos: .utility)
    private let lock = NSLock()
    private var stream: SCStream?
    private var captureGeometry: ScreenMotionCaptureGeometry?
    private var isStarting = false
    private var previousSamples: [UInt8] = []
    private var currentSamples: [UInt8] = []
    private var motion: Double = 0
    private var lastFrameAt: Date?
    private var isUnavailable = false
    private var framesPerSecond = 4
    private var lastSampleTime: CFAbsoluteTime?
    private var captureTarget: ScreenCaptureTarget?
    private var isRunning = false

    func update(configuration: SignalSamplingConfiguration) {
        queue.async { [weak self] in
            guard let self else { return }
            let targetChanged = self.captureTarget != configuration.screenCaptureTarget
            let nextFramesPerSecond = max(1, configuration.screenMotionFramesPerSecond)
            let frameRateChanged = self.framesPerSecond != nextFramesPerSecond
            self.framesPerSecond = nextFramesPerSecond
            self.captureTarget = configuration.screenCaptureTarget

            guard targetChanged || frameRateChanged, let stream = self.stream else { return }
            guard !targetChanged else {
                self.restartCapture(using: stream)
                return
            }

            if let captureGeometry = self.captureGeometry {
                let streamConfiguration = Self.streamConfiguration(
                    geometry: captureGeometry,
                    framesPerSecond: nextFramesPerSecond
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
            } else {
                self.restartCapture(using: stream)
            }
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
        let stream = queue.sync {
            let stream = self.stream
            self.stream = nil
            self.captureGeometry = nil
            self.isStarting = false
            self.isRunning = false
            self.previousSamples = []
            self.currentSamples = []
            self.lastSampleTime = nil
            return stream
        }

        Task {
            try? await stream?.stopCapture()
        }
    }

    func snapshot() -> ScreenMotionSnapshot {
        lock.lock()
        let motion = motion
        let lastFrameAt = lastFrameAt
        let isUnavailable = isUnavailable
        lock.unlock()

        let isFrozen: Bool
        if isUnavailable {
            isFrozen = false
        } else if let lastFrameAt {
            isFrozen = Date().timeIntervalSince(lastFrameAt) > 3
        } else {
            isFrozen = false
        }

        return ScreenMotionSnapshot(motion: motion, isFrozen: isFrozen, isUnavailable: isUnavailable)
    }

    private func startCapture() async {
        let framesPerSecond = currentFramesPerSecond()
        let captureTarget = currentCaptureTarget()

        guard CGPreflightScreenCaptureAccess() else {
            update(motion: 0, frameDate: nil, isUnavailable: true)
            finishStartWithoutStream(framesPerSecond: framesPerSecond, captureTarget: captureTarget)
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let selection = Self.captureSelection(
                from: content,
                target: captureTarget
            ) else {
                update(motion: 0, frameDate: nil, isUnavailable: true)
                finishStartWithoutStream(framesPerSecond: framesPerSecond, captureTarget: captureTarget)
                return
            }

            let configuration = Self.streamConfiguration(
                geometry: selection.geometry,
                framesPerSecond: framesPerSecond
            )

            let stream = SCStream(filter: selection.filter, configuration: configuration, delegate: nil)
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            try await stream.startCapture()

            finishStart(
                with: stream,
                framesPerSecond: framesPerSecond,
                captureTarget: captureTarget,
                captureGeometry: selection.geometry
            )
        } catch {
            update(motion: 0, frameDate: nil, isUnavailable: true)
            finishStartWithoutStream(framesPerSecond: framesPerSecond, captureTarget: captureTarget)
        }
    }

    private func finishStart(
        with stream: SCStream,
        framesPerSecond: Int,
        captureTarget: ScreenCaptureTarget?,
        captureGeometry: ScreenMotionCaptureGeometry
    ) {
        queue.async { [weak self] in
            guard let self else {
                Task { try? await stream.stopCapture() }
                return
            }

            self.isStarting = false
            guard self.isRunning,
                  self.framesPerSecond == framesPerSecond,
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
            self.lastSampleTime = nil
            self.update(motion: 0, frameDate: Date(), isUnavailable: false)
        }
    }

    private func finishStartWithoutStream(
        framesPerSecond: Int,
        captureTarget: ScreenCaptureTarget?
    ) {
        queue.async { [weak self] in
            guard let self else { return }

            let shouldRestart = self.isRunning
                && (self.framesPerSecond != framesPerSecond || self.captureTarget != captureTarget)
            self.isStarting = false
            if shouldRestart {
                self.start()
            }
        }
    }

    private func currentFramesPerSecond() -> Int {
        queue.sync {
            max(1, framesPerSecond)
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
        self.previousSamples = []
        self.currentSamples = []
        self.lastSampleTime = nil

        Task {
            try? await stream.stopCapture()
            self.queue.async { [weak self] in
                guard let self, self.isRunning else { return }
                self.start()
            }
        }
    }

    private static func streamConfiguration(
        geometry: ScreenMotionCaptureGeometry,
        framesPerSecond: Int
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = geometry.width(for: maxCaptureWidth)
        configuration.height = geometry.height(for: maxCaptureWidth)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(framesPerSecond))
        configuration.queueDepth = 2
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        return configuration
    }

    private static func captureSelection(
        from content: SCShareableContent,
        target: ScreenCaptureTarget?
    ) -> ScreenCaptureSelection? {
        if target?.kind == .window,
           let window = content.windows.first(where: { "window-\($0.windowID)" == target?.id }) {
            let geometry = ScreenMotionCaptureGeometry(
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

        let geometry = ScreenMotionCaptureGeometry(
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
        let frameInterval = 1.0 / Double(max(1, framesPerSecond))
        guard ScreenMotionFrameSamplingGate.shouldSample(
            now: now,
            lastSampleTime: lastSampleTime,
            interval: frameInterval
        ) else {
            return
        }
        lastSampleTime = now

        currentSamples.removeAll(keepingCapacity: true)
        Self.appendLumaSamples(from: pixelBuffer, to: &currentSamples)
        guard !currentSamples.isEmpty else { return }

        let diff = Self.normalizedDifference(previous: previousSamples, current: currentSamples)
        swap(&previousSamples, &currentSamples)

        update(motion: diff, frameDate: Date(), isUnavailable: false)
    }

    private func update(motion: Double, frameDate: Date?, isUnavailable: Bool) {
        lock.lock()
        self.motion = min(max((self.motion * 0.65) + (motion * 0.35), 0), 1)
        if let frameDate {
            self.lastFrameAt = frameDate
        }
        self.isUnavailable = isUnavailable
        lock.unlock()
    }

    private static func appendLumaSamples(from pixelBuffer: CVPixelBuffer, to samples: inout [UInt8]) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        samples.reserveCapacity(ScreenMotionLumaSamplingGrid.capacity)

        for row in 0..<ScreenMotionLumaSamplingGrid.rows {
            let y = min(height - 1, max(0, (height * row) / ScreenMotionLumaSamplingGrid.rows))
            for column in 0..<ScreenMotionLumaSamplingGrid.columns {
                let x = min(width - 1, max(0, (width * column) / ScreenMotionLumaSamplingGrid.columns))
                let offset = (y * bytesPerRow) + (x * 4)
                let blue = Double(bytes[offset])
                let green = Double(bytes[offset + 1])
                let red = Double(bytes[offset + 2])
                let luma = UInt8(min(max((0.2126 * red) + (0.7152 * green) + (0.0722 * blue), 0), 255))
                samples.append(luma)
            }
        }
    }

    private static func normalizedDifference(previous: [UInt8], current: [UInt8]) -> Double {
        guard previous.count == current.count, !current.isEmpty else { return 0 }

        var total = 0
        for index in current.indices {
            total += abs(Int(current[index]) - Int(previous[index]))
        }

        let average = Double(total) / Double(current.count)
        return min(max(average / 48, 0), 1)
    }
}

private struct ScreenCaptureSelection {
    var filter: SCContentFilter
    var geometry: ScreenMotionCaptureGeometry
}

private struct ScreenMotionCaptureGeometry {
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
