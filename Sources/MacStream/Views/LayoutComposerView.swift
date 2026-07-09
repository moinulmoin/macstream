import SwiftUI
import MacStreamCore
import AppKit
import UniformTypeIdentifiers

struct LayoutComposerView: View {
    var store: StudioStore
    @State private var isShowingBackgroundImporter = false
    @State private var isSourceFramingExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioPanelHeader(
                title: "Layout",
                systemImage: "rectangle.split.2x1",
                subtitle: "Compose the output canvas for screen and webcam scenes."
            ) {
                Button {
                    updateLayout { $0 = StudioLayoutSettings() }
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reset layout")
                .accessibilityLabel(Text("Reset layout"))
            }

            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    StudioGroupLabel(title: "Preset", systemImage: "rectangle.3.group")

                    LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 8) {
                        ForEach(StudioLayoutPreset.allCases) { preset in
                            LayoutPresetButton(
                                preset: preset,
                                isSelected: store.preferences.layoutSettings.preset == preset
                            ) {
                                updateLayout { $0.preset = preset }
                            }
                        }
                    }
                }

                backgroundControls

                StudioBadge(
                    title: layoutSummaryTitle,
                    systemImage: store.preferences.layoutSettings.preset.symbolName,
                    tint: .secondary
                )

                paddingControl

                DisclosureGroup(isExpanded: $isSourceFramingExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        sourceGapControl
                        sourceCornerRadiusControl

                        SourceViewportControls(
                            title: "Screen",
                            systemImage: "display",
                            zoom: screenZoomBinding,
                            panX: screenPanXBinding,
                            panY: screenPanYBinding
                        )

                        SourceViewportControls(
                            title: "Webcam",
                            systemImage: "video",
                            zoom: webcamZoomBinding,
                            panX: webcamPanXBinding,
                            panY: webcamPanYBinding
                        )
                    }
                    .padding(.top, 8)
                } label: {
                    Label("Source framing", systemImage: "viewfinder")
                        .font(.caption.weight(.semibold))
                }
                .accessibilityLabel(Text("Source framing controls"))
            }
        }
        .studioCard()
        .fileImporter(
            isPresented: $isShowingBackgroundImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result,
               let url = urls.first,
               let storedURL = Self.storeBackgroundImage(from: url) {
                updateLayout { $0.background = .localImage(path: storedURL.path) }
            }
        }
    }

    private var presetColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }

    private var layoutSummaryTitle: String {
        "\(store.preferences.layoutSettings.preset.shortTitle) · \(backgroundSummaryTitle)"
    }

    private var backgroundSummaryTitle: String {
        switch store.preferences.layoutSettings.background {
        case let .preset(style):
            style.title
        case .color:
            "Custom color"
        case let .localImage(path):
            path.isEmpty ? "Image" : URL(fileURLWithPath: path).lastPathComponent
        }
    }

    private var backgroundControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            StudioGroupLabel(title: "Background", systemImage: "paintpalette")

            LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 8) {
                ForEach(StudioBackgroundStyle.allCases) { style in
                    BackgroundSwatchButton(
                        style: style,
                        isSelected: store.preferences.layoutSettings.background == .preset(style)
                    ) {
                        updateLayout { $0.background = .preset(style) }
                    }
                }
            }

            HStack(spacing: 8) {
                ColorPicker(selection: customBackgroundColor, supportsOpacity: true) {
                    Label("Custom", systemImage: "eyedropper")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                .labelsHidden()
                .accessibilityLabel(Text("Custom background color"))
                .accessibilityValue(Text(customColorAccessibilityValue))

                Text("Custom color")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Label(imageBackgroundTitle, systemImage: "photo")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                Button(imageBackgroundActionTitle) {
                    isShowingBackgroundImporter = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(Text(imageBackgroundActionAccessibilityLabel))

                if hasImageBackground {
                    Button {
                        updateLayout { $0.background = .preset(.black) }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Remove background image")
                    .accessibilityLabel(Text("Remove background image"))
                }
            }
        }
    }

    private var paddingControl: some View {
        SettingSliderRow(
            title: "Padding",
            systemImage: "rectangle.inset.filled",
            value: canvasPaddingBinding,
            range: StudioLayoutSettings.minimumCanvasPadding...StudioLayoutSettings.maximumCanvasPadding,
            step: 0.01,
            valueTitle: { paddingTitle($0) },
            accessibilityLabel: "Canvas padding"
        )
    }

    private var sourceGapControl: some View {
        SettingSliderRow(
            title: "Gap",
            systemImage: "arrow.left.and.right",
            value: sourceGapBinding,
            range: StudioLayoutSettings.minimumSourceGap...StudioLayoutSettings.maximumSourceGap,
            step: 0.001,
            valueTitle: { percentTitle($0) },
            accessibilityLabel: "Source gap"
        )
    }

    private var sourceCornerRadiusControl: some View {
        SettingSliderRow(
            title: "Radius",
            systemImage: "rectangle.roundedtop",
            value: sourceCornerRadiusBinding,
            range: StudioLayoutSettings.minimumSourceCornerRadius...StudioLayoutSettings.maximumSourceCornerRadius,
            step: 0.001,
            valueTitle: { percentTitle($0) },
            accessibilityLabel: "Source corner radius"
        )
    }

    private var screenZoomBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.screenZoom },
            set: { newZoom in
                updateLayout { $0.screenZoom = newZoom }
            }
        )
    }

    private var screenPanXBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.screenViewport.panX },
            set: { newPan in
                updateLayout { $0.screenViewport.panX = newPan }
            }
        )
    }

    private var screenPanYBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.screenViewport.panY },
            set: { newPan in
                updateLayout { $0.screenViewport.panY = newPan }
            }
        )
    }

    private var canvasPaddingBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.canvasPadding },
            set: { newPadding in
                updateLayout { $0.canvasPadding = newPadding }
            }
        )
    }

    private var sourceGapBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.sourceGap },
            set: { newGap in
                updateLayout { $0.sourceGap = newGap }
            }
        )
    }

    private var sourceCornerRadiusBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.sourceCornerRadius },
            set: { newRadius in
                updateLayout { $0.sourceCornerRadius = newRadius }
            }
        )
    }

    private var webcamZoomBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.webcamZoom },
            set: { newZoom in
                updateLayout { $0.webcamZoom = newZoom }
            }
        )
    }

    private var webcamPanXBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.webcamViewport.panX },
            set: { newPan in
                updateLayout { $0.webcamViewport.panX = newPan }
            }
        )
    }

    private var webcamPanYBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.webcamViewport.panY },
            set: { newPan in
                updateLayout { $0.webcamViewport.panY = newPan }
            }
        )
    }

    private var customBackgroundColor: Binding<Color> {
        Binding(
            get: {
                Color(
                    .sRGB,
                    red: currentCustomColor.red,
                    green: currentCustomColor.green,
                    blue: currentCustomColor.blue,
                    opacity: currentCustomColor.alpha
                )
            },
            set: { newColor in
                updateLayout { $0.background = .color(Self.rgbaColor(from: newColor)) }
            }
        )
    }

    private var currentCustomColor: StudioRGBAColor {
        if case let .color(color) = store.preferences.layoutSettings.background {
            return color
        }

        return Self.rgbaColor(for: store.preferences.layoutSettings.backgroundStyle)
    }

    private var customColorAccessibilityValue: String {
        let color = currentCustomColor
        return "Red \(Int((color.red * 100).rounded())) percent, green \(Int((color.green * 100).rounded())) percent, blue \(Int((color.blue * 100).rounded())) percent, opacity \(Int((color.alpha * 100).rounded())) percent"
    }

    private var hasImageBackground: Bool {
        if case .localImage = store.preferences.layoutSettings.background { return true }
        return false
    }

    private var imageBackgroundTitle: String {
        if case let .localImage(path) = store.preferences.layoutSettings.background,
           !path.isEmpty {
            return URL(fileURLWithPath: path).lastPathComponent
        }

        return "No image"
    }

    private var imageBackgroundActionTitle: String {
        hasImageBackground ? "Replace" : "Choose"
    }

    private var imageBackgroundActionAccessibilityLabel: String {
        hasImageBackground ? "Replace background image" : "Choose background image"
    }

    private func updateLayout(_ update: (inout StudioLayoutSettings) -> Void) {
        var preferences = store.preferences
        var layoutSettings = preferences.layoutSettings
        update(&layoutSettings)
        guard layoutSettings != preferences.layoutSettings else { return }

        preferences.layoutSettings = layoutSettings
        store.updatePreferences(preferences)
    }

    private func zoomTitle(_ value: Double) -> String {
        "\(Int((StudioLayoutSettings.normalizedSourceZoom(value) * 100).rounded()))%"
    }

    private func paddingTitle(_ value: Double) -> String {
        "\(Int((StudioLayoutSettings.normalizedCanvasPadding(value) * 100).rounded()))%"
    }

    private func percentTitle(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    fileprivate static func rgbaColor(for style: StudioBackgroundStyle) -> StudioRGBAColor {
        switch style {
        case .black:
            StudioRGBAColor(red: 0, green: 0, blue: 0)
        case .studio:
            StudioRGBAColor(red: 0.06, green: 0.07, blue: 0.10)
        case .stage:
            StudioRGBAColor(red: 0.08, green: 0.02, blue: 0.04)
        case .warm:
            StudioRGBAColor(red: 0.14, green: 0.10, blue: 0.06)
        }
    }

    fileprivate static func rgbaColor(from color: Color) -> StudioRGBAColor {
        let nsColor = NSColor(color).usingColorSpace(.sRGB) ?? .black
        return StudioRGBAColor(
            red: nsColor.redComponent,
            green: nsColor.greenComponent,
            blue: nsColor.blueComponent,
            alpha: nsColor.alphaComponent
        )
    }

    private static func storeBackgroundImage(from sourceURL: URL) -> URL? {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fileManager = FileManager.default
            let applicationSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let directory = applicationSupport
                .appendingPathComponent("MacStream", isDirectory: true)
                .appendingPathComponent("Canvas", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let pathExtension = sourceURL.pathExtension.isEmpty ? "image" : sourceURL.pathExtension.lowercased()
            let importID = UUID().uuidString
            let destination = directory.appendingPathComponent("background-\(importID).\(pathExtension)")
            let temporary = directory.appendingPathComponent(".import-\(importID).\(pathExtension)")
            try fileManager.copyItem(at: sourceURL, to: temporary)

            for existing in try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) where existing != temporary {
                try? fileManager.removeItem(at: existing)
            }
            try fileManager.moveItem(at: temporary, to: destination)
            return destination
        } catch {
            return nil
        }
    }
}

private struct SettingSliderRow: View {
    var title: String
    var systemImage: String
    var value: Binding<Double>
    var range: ClosedRange<Double>
    var step: Double
    var valueTitle: (Double) -> String
    var accessibilityLabel: String
    @State private var draftValue: Double?

    var body: some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 72, alignment: .leading)

            Slider(value: draftBinding, in: range, step: step) { isEditing in
                guard !isEditing, let draftValue else { return }
                value.wrappedValue = draftValue
                self.draftValue = nil
            }
                .accessibilityLabel(Text(accessibilityLabel))
                .accessibilityValue(Text(valueTitle(displayValue)))

            Text(valueTitle(displayValue))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var displayValue: Double {
        draftValue ?? value.wrappedValue
    }

    private var draftBinding: Binding<Double> {
        Binding(
            get: { displayValue },
            set: { draftValue = $0 }
        )
    }
}

private struct SourceViewportControls: View {
    var title: String
    var systemImage: String
    var zoom: Binding<Double>
    var panX: Binding<Double>
    var panY: Binding<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            SettingSliderRow(
                title: "Zoom",
                systemImage: "plus.magnifyingglass",
                value: zoom,
                range: StudioLayoutSettings.minimumSourceZoom...StudioLayoutSettings.maximumSourceZoom,
                step: 0.05,
                valueTitle: { zoomTitle($0) },
                accessibilityLabel: "\(title) zoom"
            )

            SettingSliderRow(
                title: "Pan X",
                systemImage: "arrow.left.and.right",
                value: panX,
                range: StudioLayoutSettings.minimumSourcePan...StudioLayoutSettings.maximumSourcePan,
                step: 0.05,
                valueTitle: { panTitle($0) },
                accessibilityLabel: "\(title) horizontal pan"
            )

            SettingSliderRow(
                title: "Pan Y",
                systemImage: "arrow.up.and.down",
                value: panY,
                range: StudioLayoutSettings.minimumSourcePan...StudioLayoutSettings.maximumSourcePan,
                step: 0.05,
                valueTitle: { panTitle($0) },
                accessibilityLabel: "\(title) vertical pan"
            )
        }
    }

    private func zoomTitle(_ value: Double) -> String {
        "\(Int((StudioLayoutSettings.normalizedSourceZoom(value) * 100).rounded()))%"
    }

    private func panTitle(_ value: Double) -> String {
        let normalized = StudioLayoutSettings.normalizedSourcePan(value)
        return "\(Int((normalized * 100).rounded()))%"
    }
}

private struct LayoutPresetButton: View {
    var preset: StudioLayoutPreset
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                LayoutPresetGlyph(preset: preset, isSelected: isSelected)
                    .frame(width: 42, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.shortTitle)
                        .font(.caption.weight(.semibold))
                    Text(presetDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(buttonBackground, in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous)
                    .strokeBorder(isSelected ? StudioPalette.accent.opacity(0.72) : Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(preset.title)
        .accessibilityLabel(Text(preset.title))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var buttonBackground: Color {
        isSelected ? StudioPalette.accent.opacity(0.18) : Color.primary.opacity(0.05)
    }

    private var presetDetail: String {
        switch preset {
        case .pictureInPicture: "Floating cam"
        case .screen70Webcam30: "Screen lead"
        case .evenSplit: "Equal split"
        case .screen30Webcam70: "Cam lead"
        }
    }
}

private struct LayoutPresetGlyph: View {
    var preset: StudioLayoutPreset
    var isSelected: Bool

    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.black.opacity(0.55))

                if preset.isSplit {
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(screenColor)
                            .frame(width: max(6, rect.width * preset.screenFraction))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(webcamColor)
                    }
                    .padding(3)
                } else {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(screenColor)
                        .padding(3)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(webcamColor)
                        .frame(width: rect.width * 0.34, height: rect.height * 0.34)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(5)
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(isSelected ? StudioPalette.accent : Color.white.opacity(0.18), lineWidth: 1)
        }
    }

    private var screenColor: Color {
        isSelected ? StudioPalette.info.opacity(0.78) : Color.white.opacity(0.30)
    }

    private var webcamColor: Color {
        isSelected ? StudioPalette.recording.opacity(0.88) : Color.white.opacity(0.52)
    }
}

private struct BackgroundSwatchButton: View {
    var style: StudioBackgroundStyle
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(swatchFill)
                    .frame(width: 18, height: 18)
                    .overlay {
                        Circle()
                            .strokeBorder(isSelected ? StudioPalette.accent : Color.white.opacity(0.24), lineWidth: isSelected ? 2 : 1)
                    }
                    .shadow(color: isSelected ? StudioPalette.accent.opacity(0.38) : .clear, radius: 5)

                Text(style.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(isSelected ? StudioPalette.accent.opacity(0.16) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous)
                    .strokeBorder(isSelected ? StudioPalette.accent.opacity(0.70) : Color.white.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(style.title)
        .accessibilityLabel(Text("\(style.title) background"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var swatchFill: Color {
        switch style {
        case .black:
            Color.black
        case .studio:
            Color(red: 0.06, green: 0.07, blue: 0.10)
        case .stage:
            Color(red: 0.08, green: 0.02, blue: 0.04)
        case .warm:
            Color(red: 0.14, green: 0.10, blue: 0.06)
        }
    }
}
