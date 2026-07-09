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
                Picker("Preset", selection: presetBinding) {
                    ForEach(StudioLayoutPreset.allCases) { preset in
                        Label(preset.shortTitle, systemImage: preset.symbolName)
                            .tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help("Choose the screen and webcam arrangement")
                .accessibilityLabel(Text("Layout preset"))
                .accessibilityValue(Text(store.preferences.layoutSettings.preset.title))

                HStack(spacing: 10) {
                    Picker("Background", selection: backgroundBinding) {
                        ForEach(StudioBackgroundStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.menu)
                    .help("Choose the canvas background")
                    .accessibilityLabel(Text("Canvas background"))

                    Spacer(minLength: 8)

                    StudioBadge(
                        title: store.preferences.layoutSettings.preset.shortTitle,
                        systemImage: store.preferences.layoutSettings.preset.symbolName,
                        tint: .secondary
                    )
                }

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

    private var presetBinding: Binding<StudioLayoutPreset> {
        Binding(
            get: { store.preferences.layoutSettings.preset },
            set: { newPreset in
                updateLayout { $0.preset = newPreset }
            }
        )
    }

    private var backgroundBinding: Binding<StudioBackgroundStyle> {
        Binding(
            get: { store.preferences.layoutSettings.backgroundStyle },
            set: { newStyle in
                updateLayout { $0.backgroundStyle = newStyle }
            }
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
}
