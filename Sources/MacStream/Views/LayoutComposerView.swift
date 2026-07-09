import SwiftUI
import MacStreamCore

struct LayoutComposerView: View {
    var store: StudioStore

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

                VStack(alignment: .leading, spacing: 8) {
                    StudioGroupLabel(title: "Background", systemImage: "paintpalette")

                    LazyVGrid(columns: presetColumns, alignment: .leading, spacing: 8) {
                        ForEach(StudioBackgroundStyle.allCases) { style in
                            BackgroundSwatchButton(
                                style: style,
                                isSelected: store.preferences.layoutSettings.backgroundStyle == style
                            ) {
                                updateLayout { $0.backgroundStyle = style }
                            }
                        }
                    }
                }

                StudioBadge(
                    title: layoutSummaryTitle,
                    systemImage: store.preferences.layoutSettings.preset.symbolName,
                    tint: .secondary
                )

                paddingControl

                zoomControl(
                    title: "Screen",
                    systemImage: "display",
                    value: screenZoomBinding
                )

                zoomControl(
                    title: "Webcam",
                    systemImage: "video",
                    value: webcamZoomBinding
                )
            }
        }
        .studioCard()
    }

    private var presetColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]
    }

    private var layoutSummaryTitle: String {
        "\(store.preferences.layoutSettings.preset.shortTitle) · \(store.preferences.layoutSettings.backgroundStyle.title)"
    }

    private func zoomControl(
        title: String,
        systemImage: String,
        value: Binding<Double>
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            Slider(
                value: value,
                in: StudioLayoutSettings.minimumSourceZoom...StudioLayoutSettings.maximumSourceZoom,
                step: 0.05
            )
            .accessibilityLabel(Text("\(title) zoom"))
            .accessibilityValue(Text(zoomTitle(value.wrappedValue)))

            Text(zoomTitle(value.wrappedValue))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private var paddingControl: some View {
        HStack(spacing: 8) {
            Label("Padding", systemImage: "rectangle.inset.filled")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            Slider(
                value: canvasPaddingBinding,
                in: StudioLayoutSettings.minimumCanvasPadding...StudioLayoutSettings.maximumCanvasPadding,
                step: 0.01
            )
            .accessibilityLabel(Text("Canvas padding"))
            .accessibilityValue(Text(paddingTitle(store.preferences.layoutSettings.canvasPadding)))

            Text(paddingTitle(store.preferences.layoutSettings.canvasPadding))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }

    private var screenZoomBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.screenZoom },
            set: { newZoom in
                updateLayout { $0.screenZoom = newZoom }
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

    private var webcamZoomBinding: Binding<Double> {
        Binding(
            get: { store.preferences.layoutSettings.webcamZoom },
            set: { newZoom in
                updateLayout { $0.webcamZoom = newZoom }
            }
        )
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
