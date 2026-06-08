import SwiftUI
import MacStreamCore

struct SourceRackView: View {
    var store: StudioStore
    @SceneStorage("MacStream.SourceRackView.showMoreSources") private var showMoreSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Sources", systemImage: "slider.horizontal.3")
                        .font(.headline)

                    Text("Keep the required inputs armed and balanced before output starts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StudioBadge(title: "\(primarySources.count) primary", systemImage: "switch.2", tint: .secondary)
            }

            sourceRows(for: primarySources)

            if !secondarySources.isEmpty {
                DisclosureGroup(isExpanded: $showMoreSources) {
                    sourceRows(for: secondarySources)
                        .padding(.top, 8)
                } label: {
                    Label("More sources", systemImage: "ellipsis.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .studioCard()
    }

    private var primarySources: [StudioSource] {
        store.sources.filter { source in
            switch store.setupRole(for: source.kind) {
            case .required, .recommended:
                return true
            case .optional, .unused:
                return false
            }
        }
    }

    private var secondarySources: [StudioSource] {
        store.sources.filter { source in
            !primarySources.contains { $0.id == source.id }
        }
    }

    private func sourceRows(for sources: [StudioSource]) -> some View {
        ForEach(sources) { source in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(source.title)
                                    .font(.subheadline.weight(.semibold))

                                StudioBadge(title: store.setupRole(for: source.kind).title, systemImage: nil, tint: setupRoleTint(for: source))
                            }

                            Text(source.kind.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: source.kind.symbolName)
                            .foregroundStyle(source.isEnabled ? .primary : .secondary)
                    }

                    Spacer(minLength: 8)

                    Button {
                        store.toggleSource(source)
                    } label: {
                        Label(source.isEnabled ? "On" : "Off", systemImage: source.isEnabled ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!store.canToggleSource(source))
                    .help(sourceToggleHelp(for: source))
                    .accessibilityLabel(Text("\(source.title) source"))
                    .accessibilityValue(Text(source.isEnabled ? "On" : "Off"))
                    .accessibilityHint(Text(sourceToggleHelp(for: source)))
                }

                if source.kind.supportsLevelControl {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { source.level },
                                set: { store.updateLevel(for: source, level: $0) }
                            ),
                            in: 0...1,
                            step: 0.01
                        )
                        .disabled(!store.canAdjustSourceLevel(source))
                        .help(sourceLevelHelp(for: source))
                        .accessibilityLabel(Text("\(source.title) level"))
                        .accessibilityValue(Text(sourceLevelTitle(for: source)))
                        .accessibilityHint(Text(sourceLevelHelp(for: source)))

                        Text(sourceLevelTitle(for: source))
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 42, alignment: .trailing)
                    }
                }

                if source.kind == .camera, source.isEnabled {
                    CameraEnhancementControls(
                        settings: Binding(
                            get: { store.preferences.cameraEnhancements },
                            set: { store.updateCameraEnhancements($0) }
                        )
                    )
                    .padding(10)
                    .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(10)
            .background(source.isEnabled ? Color.accentColor.opacity(0.06) : Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder((source.isEnabled ? Color.accentColor : Color.secondary).opacity(0.10), lineWidth: 1)
            }
        }
    }

    private func sourceLevelTitle(for source: StudioSource) -> String {
        "\(Int((source.level * 100).rounded()))%"
    }

    private func setupRoleTint(for source: StudioSource) -> Color {
        switch store.setupRole(for: source.kind) {
        case .required: .orange
        case .recommended: .accentColor
        case .optional: .secondary
        case .unused: .secondary
        }
    }

    private func sourceToggleHelp(for source: StudioSource) -> String {
        if store.canToggleSource(source) {
            return source.isEnabled ? "Turn source off" : "Turn source on"
        }

        return "Switch scenes or stop capture before turning off a required source"
    }

    private func sourceLevelHelp(for source: StudioSource) -> String {
        if store.canAdjustSourceLevel(source) {
            return "Adjust source level"
        }

        if !source.isEnabled {
            return "Turn source on before adjusting level"
        }

        return "Switch scenes or stop capture before adjusting a required source"
    }
}

private struct CameraEnhancementControls: View {
    @Binding var settings: CameraEnhancementSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Mirror", isOn: mirrorBinding)
                    .toggleStyle(.checkbox)
                    .help("Mirror the local camera preview")

                Toggle("Auto Light", isOn: autoLightBinding)
                    .toggleStyle(.checkbox)
                    .help("Use preview lighting plus camera auto exposure, focus, and white balance")
            }
            .font(.caption)

            Picker("Rotation", selection: rotationBinding) {
                ForEach(CameraPreviewRotation.allCases) { rotation in
                    Text(rotation.title).tag(rotation)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .help("Rotate the local camera preview")

            if settings.usesAutoLight {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max")
                        .foregroundStyle(.secondary)
                    Slider(value: autoLightAmountBinding, in: 0...1, step: 0.01)
                        .help("Adjust preview lighting strength")
                }
            }
        }
        .padding(.top, 2)
    }

    private var mirrorBinding: Binding<Bool> {
        Binding(
            get: { settings.mirrorsPreview },
            set: { settings.mirrorsPreview = $0 }
        )
    }

    private var autoLightBinding: Binding<Bool> {
        Binding(
            get: { settings.usesAutoLight },
            set: { settings.usesAutoLight = $0 }
        )
    }

    private var rotationBinding: Binding<CameraPreviewRotation> {
        Binding(
            get: { settings.rotation },
            set: { settings.rotation = $0 }
        )
    }

    private var autoLightAmountBinding: Binding<Double> {
        Binding(
            get: { settings.autoLightAmount },
            set: { settings.autoLightAmount = $0 }
        )
    }
}
