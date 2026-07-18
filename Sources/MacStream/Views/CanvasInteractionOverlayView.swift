import AppKit
import SwiftUI
import MacStreamCore

struct CanvasInteractionOverlayView: View {
    @Environment(\.scenePhase) private var scenePhase

    var scene: StudioScene
    var persistedSettings: StudioLayoutSettings
    @Binding var draftSettings: StudioLayoutSettings?
    var sourceSize: (SourceKind) -> CGSize
    var onPreview: (StudioLayoutSettings?) -> Void
    var onCommit: (StudioLayoutSettings) -> Void

    @State private var selectedSource: SourceKind?
    @State private var manipulationMode = CanvasManipulationMode.move
    @State private var dragStartSettings: StudioLayoutSettings?
    @State private var magnificationStartSettings: StudioLayoutSettings?
    @State private var activeGesture: CanvasActiveGesture?
    @State private var lastPipelinePreviewAt = Date.distantPast

    private static let coordinateSpaceName = "MacStream.PreviewCanvas"

    var body: some View {
        GeometryReader { proxy in
            let settings = activeSettings
            let layout = StudioCanvasLayout(size: proxy.size, settings: settings)

            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSource = nil
                    }

                if let screenRect = previewRect(for: .screen, in: layout) {
                    sourceInteractionRegion(.screen, rect: screenRect, canvasSize: proxy.size)
                }

                if let webcamRect = previewRect(for: .camera, in: layout) {
                    sourceInteractionRegion(.camera, rect: webcamRect, canvasSize: proxy.size)
                }

                if let selectedSource,
                   let selectedRect = previewRect(for: selectedSource, in: layout) {
                    selectionChrome(
                        source: selectedSource,
                        rect: selectedRect,
                        canvasSize: proxy.size
                    )

                    editorToolbar(for: selectedSource, settings: settings)
                        .padding(10)
                }
            }
            .coordinateSpace(name: Self.coordinateSpaceName)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Canvas editor"))
        .onChange(of: scene.id) { _, _ in
            cancelInteraction()
            selectedSource = nil
        }
        .onDisappear {
            cancelInteraction()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                cancelInteraction()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            cancelInteraction()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            cancelInteraction()
        }
    }

    private var activeSettings: StudioLayoutSettings {
        draftSettings ?? persistedSettings
    }

    @ViewBuilder
    private func sourceInteractionRegion(
        _ source: SourceKind,
        rect: CGRect,
        canvasSize: CGSize
    ) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .gesture(dragGesture(for: source, sourceRect: rect, canvasSize: canvasSize))
            .simultaneousGesture(
                magnificationGesture(
                    for: source,
                    sourceRect: rect,
                    canvasSize: canvasSize
                )
            )
            .onTapGesture(count: 2) {
                select(source)
                resetSelectedSource()
            }
            .onTapGesture {
                select(source)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text("Edit \(source.title) on canvas"))
            .accessibilityHint(Text(accessibilityHint(for: source)))
            .accessibilityAction {
                select(source)
            }
    }

    @ViewBuilder
    private func selectionChrome(
        source: SourceKind,
        rect: CGRect,
        canvasSize: CGSize
    ) -> some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(
                StudioPalette.accent,
                style: StrokeStyle(lineWidth: 2, dash: [7, 4])
            )
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)

        if source == .camera,
           canMovePresenter(settings: activeSettings),
           manipulationMode == .move {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(.black.opacity(0.78))
                .clipShape(Circle())
                .overlay {
                    Circle().stroke(StudioPalette.accent, lineWidth: 2)
                }
                .position(
                    x: min(max(13, rect.maxX), canvasSize.width - 13),
                    y: min(max(13, rect.maxY), canvasSize.height - 13)
                )
                .gesture(resizePresenterGesture(canvasSize: canvasSize))
                .help("Resize webcam")
                .accessibilityLabel(Text("Resize webcam"))
                .accessibilityValue(Text("\(Int((activeSettings.presenterComposition.scale * 100).rounded())) percent"))
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment:
                        adjustSelectedScale(by: 1)
                    case .decrement:
                        adjustSelectedScale(by: -1)
                    @unknown default:
                        break
                    }
                }
        }
    }

    private func editorToolbar(
        for source: SourceKind,
        settings: StudioLayoutSettings
    ) -> some View {
        HStack(spacing: 3) {
            Image(systemName: source.symbolName)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 27, height: 27)
                .accessibilityHidden(true)

            if source == .camera, canMovePresenter(settings: settings) {
                toolbarButton(
                    systemImage: "arrow.up.and.down.and.arrow.left.and.right",
                    label: "Move webcam",
                    isSelected: manipulationMode == .move
                ) {
                    manipulationMode = .move
                }

                toolbarButton(
                    systemImage: "viewfinder",
                    label: "Reframe webcam",
                    isSelected: manipulationMode == .reframe
                ) {
                    manipulationMode = .reframe
                }

                Divider()
                    .frame(height: 18)
                    .padding(.horizontal, 2)
            }

            toolbarButton(
                systemImage: "minus.magnifyingglass",
                label: decreaseLabel(for: source)
            ) {
                adjustSelectedScale(by: -1)
            }

            toolbarButton(
                systemImage: "plus.magnifyingglass",
                label: increaseLabel(for: source)
            ) {
                adjustSelectedScale(by: 1)
            }

            toolbarButton(
                systemImage: "arrow.counterclockwise",
                label: "Reset selected source"
            ) {
                resetSelectedSource()
            }
        }
        .padding(4)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.22), radius: 8, y: 3)
        .fixedSize()
    }

    private func toolbarButton(
        systemImage: String,
        label: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 27, height: 27)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? StudioPalette.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(Text(label))
    }

    private func dragGesture(
        for source: SourceKind,
        sourceRect: CGRect,
        canvasSize: CGSize
    ) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if activeGesture == nil { activeGesture = .drag }
                guard activeGesture == .drag else { return }
                select(source)
                let start = gestureStartSettings(for: &dragStartSettings)
                var updated = start

                if source == .camera,
                   canMovePresenter(settings: start),
                   manipulationMode == .move {
                    let startLayout = StudioCanvasLayout(size: canvasSize, settings: start)
                    let startPresenterRect = startLayout.presenterComposition.presenterRect
                    let outputPoint = CGPoint(
                        x: startPresenterRect.midX + value.translation.width,
                        y: startPresenterRect.midY - value.translation.height
                    )
                    updated.presenterComposition.placement = .manual
                    updated.presenterComposition.manualPosition = startLayout
                        .normalizedContentPoint(forOutputPoint: outputPoint)
                } else {
                    updateViewport(
                        for: source,
                        in: &updated,
                        from: start,
                        translation: value.translation,
                        sourceRect: sourceRect
                    )
                }

                draftSettings = updated
                previewDraft(updated)
            }
            .onEnded { _ in
                guard activeGesture == .drag else { return }
                activeGesture = nil
                dragStartSettings = nil
                commitDraft()
            }
    }

    private func magnificationGesture(
        for source: SourceKind,
        sourceRect: CGRect,
        canvasSize: CGSize
    ) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if activeGesture == nil { activeGesture = .magnification }
                guard activeGesture == .magnification else { return }
                select(source)
                let start = gestureStartSettings(for: &magnificationStartSettings)
                var updated = start
                let factor = Double(value.magnification)

                if source == .camera,
                   canMovePresenter(settings: start),
                   manipulationMode == .move {
                    updated.presenterComposition.scale = start.presenterComposition.scale * factor
                    let startLayout = StudioCanvasLayout(size: canvasSize, settings: start)
                    let startRect = startLayout.presenterComposition.presenterRect
                    let resizedLayout = StudioCanvasLayout(size: canvasSize, settings: updated)
                    let resizedRect = resizedLayout.presenterComposition.presenterRect
                    updated.presenterComposition.placement = .manual
                    updated.presenterComposition.manualPosition = startLayout.manualPresenterPosition(
                        resizingFrom: startRect,
                        to: resizedRect.size,
                        preservingUnitAnchor: StudioNormalizedPoint(
                            x: value.startAnchor.x,
                            y: 1 - value.startAnchor.y
                        )
                    )
                } else {
                    var viewport = viewport(for: source, in: start)
                    let geometry = StudioSourceViewportGeometry(
                        sourceSize: sourceSize(source),
                        targetSize: sourceRect.size,
                        viewport: viewport
                    )
                    let anchor = CGPoint(
                        x: (value.startAnchor.x - 0.5) * sourceRect.width,
                        y: (value.startAnchor.y - 0.5) * sourceRect.height
                    )
                    viewport = geometry.viewport(
                        settingZoom: viewport.zoom * factor,
                        preservingCanvasPoint: anchor,
                        in: viewport
                    )
                    setViewport(viewport, for: source, in: &updated)
                }

                draftSettings = updated
                previewDraft(updated)
            }
            .onEnded { _ in
                guard activeGesture == .magnification else { return }
                activeGesture = nil
                magnificationStartSettings = nil
                commitDraft()
            }
    }

    private func resizePresenterGesture(canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if activeGesture == nil { activeGesture = .resize }
                guard activeGesture == .resize else { return }
                let start = gestureStartSettings(for: &dragStartSettings)
                var updated = start
                let horizontalDelta = value.translation.width
                let verticalDelta = value.translation.height * (16.0 / 9.0)
                let scaleDelta = Double((horizontalDelta + verticalDelta) / 2 / max(1, canvasSize.width))
                updated.presenterComposition.scale = start.presenterComposition.scale + scaleDelta
                draftSettings = updated
                previewDraft(updated)
            }
            .onEnded { _ in
                guard activeGesture == .resize else { return }
                activeGesture = nil
                dragStartSettings = nil
                commitDraft()
            }
    }

    private func gestureStartSettings(
        for storage: inout StudioLayoutSettings?
    ) -> StudioLayoutSettings {
        if let storage { return storage }
        let start = activeSettings
        storage = start
        return start
    }

    private func updateViewport(
        for source: SourceKind,
        in updated: inout StudioLayoutSettings,
        from start: StudioLayoutSettings,
        translation: CGSize,
        sourceRect: CGRect
    ) {
        var viewport = viewport(for: source, in: start)
        let geometry = StudioSourceViewportGeometry(
            sourceSize: sourceSize(source),
            targetSize: sourceRect.size,
            viewport: viewport
        )
        viewport = geometry.viewport(
            applyingCanvasTranslation: translation,
            to: viewport
        )
        setViewport(viewport, for: source, in: &updated)
    }

    private func viewport(
        for source: SourceKind,
        in settings: StudioLayoutSettings
    ) -> StudioSourceViewportSettings {
        source == .camera ? settings.webcamViewport : settings.screenViewport
    }

    private func setViewport(
        _ viewport: StudioSourceViewportSettings,
        for source: SourceKind,
        in settings: inout StudioLayoutSettings
    ) {
        if source == .camera {
            settings.webcamViewport = viewport
        } else {
            settings.screenViewport = viewport
        }
    }

    private func select(_ source: SourceKind) {
        guard selectedSource != source else { return }
        selectedSource = source
        manipulationMode = source == .camera && canMovePresenter(settings: activeSettings)
            ? .move
            : .reframe
    }

    private func adjustSelectedScale(by direction: Double) {
        guard let selectedSource else { return }
        var updated = activeSettings

        if selectedSource == .camera,
           canMovePresenter(settings: updated),
           manipulationMode == .move {
            updated.presenterComposition.scale += direction * 0.03
        } else {
            var viewport = viewport(for: selectedSource, in: updated)
            viewport.zoom += direction * 0.10
            setViewport(viewport, for: selectedSource, in: &updated)
        }

        commit(updated)
    }

    private func resetSelectedSource() {
        guard let selectedSource else { return }
        var updated = activeSettings

        if selectedSource == .camera,
           canMovePresenter(settings: updated),
           manipulationMode == .move {
            updated.presenterComposition.placement = .right
            updated.presenterComposition.manualPosition = StudioNormalizedPoint(x: 0.82, y: 0.24)
            updated.presenterComposition.scale = StudioPresenterCompositionSettings.defaultScale
        } else {
            setViewport(StudioSourceViewportSettings(), for: selectedSource, in: &updated)
        }

        commit(updated)
    }

    private func commitDraft() {
        guard let draftSettings else { return }
        commit(draftSettings)
    }

    private func commit(_ settings: StudioLayoutSettings) {
        draftSettings = nil
        guard settings != persistedSettings else {
            onPreview(nil)
            return
        }
        onCommit(settings)
    }

    private func previewDraft(_ settings: StudioLayoutSettings) {
        let now = Date()
        guard now.timeIntervalSince(lastPipelinePreviewAt) >= (1.0 / 30.0) else { return }
        lastPipelinePreviewAt = now
        onPreview(settings)
    }

    private func cancelInteraction() {
        guard draftSettings != nil || activeGesture != nil else { return }
        draftSettings = nil
        dragStartSettings = nil
        magnificationStartSettings = nil
        activeGesture = nil
        onPreview(nil)
    }

    private func previewRect(
        for source: SourceKind,
        in layout: StudioCanvasLayout
    ) -> CGRect? {
        let outputRect: CGRect

        switch (scene.kind, source) {
        case (.face, .camera):
            outputRect = layout.contentRect
        case (.screenOnly, .screen):
            outputRect = layout.contentRect
        case (.screenAndFace, .screen):
            outputRect = layout.presenterComposition.screenRect
        case (.screenAndFace, .camera):
            outputRect = layout.presenterComposition.presenterRect
        default:
            return nil
        }

        return CGRect(
            x: outputRect.minX,
            y: layout.outputRect.height - outputRect.maxY,
            width: outputRect.width,
            height: outputRect.height
        )
    }

    private func canMovePresenter(settings: StudioLayoutSettings) -> Bool {
        guard scene.kind == .screenAndFace else { return false }
        return settings.presenterComposition.mode == .presenterOverlay
            || settings.preset == .pictureInPicture
    }

    private func accessibilityHint(for source: SourceKind) -> String {
        if source == .camera, canMovePresenter(settings: activeSettings) {
            return manipulationMode == .move
                ? "Drag to move. Pinch to resize."
                : "Drag to crop. Pinch to zoom."
        }
        return "Drag to crop. Pinch to zoom."
    }

    private func decreaseLabel(for source: SourceKind) -> String {
        if source == .camera,
           canMovePresenter(settings: activeSettings),
           manipulationMode == .move {
            return "Make webcam smaller"
        }
        return "Zoom out \(source.title.lowercased())"
    }

    private func increaseLabel(for source: SourceKind) -> String {
        if source == .camera,
           canMovePresenter(settings: activeSettings),
           manipulationMode == .move {
            return "Make webcam larger"
        }
        return "Zoom in \(source.title.lowercased())"
    }
}

private enum CanvasManipulationMode {
    case move
    case reframe
}

private enum CanvasActiveGesture {
    case drag
    case magnification
    case resize
}
