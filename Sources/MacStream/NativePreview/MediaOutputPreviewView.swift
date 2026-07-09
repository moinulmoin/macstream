import AppKit
@preconcurrency import AVFoundation
import MacStreamCore
import SwiftUI

struct MediaOutputPreviewView: NSViewRepresentable {
    var source: MediaPreviewFrameSource
    var maximumFramesPerSecond: Int

    func makeNSView(context: Context) -> MediaOutputPreviewNSView {
        MediaOutputPreviewNSView(
            source: source,
            maximumFramesPerSecond: maximumFramesPerSecond
        )
    }

    func updateNSView(_ nsView: MediaOutputPreviewNSView, context: Context) {
        nsView.update(
            source: source,
            maximumFramesPerSecond: maximumFramesPerSecond
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: MediaOutputPreviewNSView,
        context: Context
    ) -> CGSize? {
        let aspectRatio = 16.0 / 9.0

        switch (proposal.width, proposal.height) {
        case let (width?, height?):
            let fittedWidth = min(width, height * aspectRatio)
            return CGSize(width: fittedWidth, height: fittedWidth / aspectRatio)
        case let (width?, nil):
            return CGSize(width: width, height: width / aspectRatio)
        case let (nil, height?):
            return CGSize(width: height * aspectRatio, height: height)
        case (nil, nil):
            return nil
        }
    }

    static func dismantleNSView(_ nsView: MediaOutputPreviewNSView, coordinator: ()) {
        nsView.disconnect()
    }
}

final class MediaOutputPreviewNSView: NSView {
    private let previewLayer = AVSampleBufferDisplayLayer()
    private let controller: MediaOutputPreviewController

    init(source: MediaPreviewFrameSource, maximumFramesPerSecond: Int) {
        controller = MediaOutputPreviewController(
            renderer: previewLayer.sampleBufferRenderer,
            source: source,
            maximumFramesPerSecond: maximumFramesPerSecond
        )
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.masksToBounds = true
        previewLayer.backgroundColor = NSColor.black.cgColor
        previewLayer.masksToBounds = true
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            controller.disconnect()
        } else {
            controller.connect()
        }
    }

    func update(source: MediaPreviewFrameSource, maximumFramesPerSecond: Int) {
        controller.update(
            source: source,
            maximumFramesPerSecond: maximumFramesPerSecond
        )
    }

    func disconnect() {
        controller.disconnect()
    }
}

private final class MediaOutputPreviewController: @unchecked Sendable {
    private let renderer: AVSampleBufferVideoRenderer
    private var source: MediaPreviewFrameSource
    private var maximumFramesPerSecond: Int
    private var subscription: MediaPreviewFrameSubscription?
    private var wantsConnection = false

    init(
        renderer: AVSampleBufferVideoRenderer,
        source: MediaPreviewFrameSource,
        maximumFramesPerSecond: Int
    ) {
        self.renderer = renderer
        self.source = source
        self.maximumFramesPerSecond = maximumFramesPerSecond
    }

    func connect() {
        wantsConnection = true
        guard subscription == nil else { return }
        subscription = source.subscribe(maximumFramesPerSecond: maximumFramesPerSecond) { [weak renderer] sampleBuffer in
            guard let renderer else { return }
            if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
                renderer.flush()
            }
            guard renderer.isReadyForMoreMediaData else { return }
            renderer.enqueue(sampleBuffer)
        }
    }

    func update(source: MediaPreviewFrameSource, maximumFramesPerSecond: Int) {
        if self.source !== source {
            unsubscribe()
            self.source = source
        }
        self.maximumFramesPerSecond = maximumFramesPerSecond
        if let subscription {
            source.update(subscription, maximumFramesPerSecond: maximumFramesPerSecond)
        } else if wantsConnection {
            connect()
        }
    }

    func disconnect() {
        wantsConnection = false
        unsubscribe()
        renderer.flush()
    }

    private func unsubscribe() {
        if let subscription {
            source.unsubscribe(subscription)
        }
        subscription = nil
    }
}
