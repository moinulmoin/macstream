import SwiftUI
import MacStreamCore

struct SourceRackView: View {
    var store: StudioStore
    @SceneStorage("MacStream.SourceRackView.showMoreSources") private var showMoreSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StudioPanelHeader(
                title: "Sources",
                systemImage: "slider.horizontal.3",
                subtitle: "Choose the inputs you want armed before output starts."
            ) {
                HStack(spacing: 8) {
                    StudioBadge(title: "\(primarySources.count) primary", systemImage: "switch.2", tint: .secondary)
                    refreshDevicesButton
                }
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
                            Text(source.title)
                                .font(.subheadline.weight(.semibold))

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

                deviceSelector(for: source.kind)

                if source.kind == .microphone, source.isEnabled {
                    MicrophoneLevelMeterView(
                        level: store.latestSignals.speechLevel,
                        title: "Input level",
                        isActive: store.sourceLevel(.microphone) > 0 && store.selectedMicrophoneDeviceID != nil
                    )
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

    private func sourceToggleHelp(for source: StudioSource) -> String {
        if store.canToggleSource(source) {
            return source.isEnabled ? "Turn source off" : "Turn source on"
        }

        return "Stop capture before turning off a source used by the current scene"
    }

    private func sourceLevelHelp(for source: StudioSource) -> String {
        if store.canAdjustSourceLevel(source) {
            return "Adjust source level"
        }

        if !source.isEnabled {
            return "Turn source on before adjusting level"
        }

        return "Stop capture before adjusting a source used by the current scene"
    }

    private var refreshDevicesButton: some View {
        Button {
            store.scanCaptureDevices()
        } label: {
            if store.isScanningCapture {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!store.canScanCaptureDevices)
        .help(store.captureScanBlockedReason ?? "Re-scan cameras, microphones, and screens")
        .accessibilityLabel(Text(store.isScanningCapture ? "Refreshing devices" : "Refresh devices"))
        .accessibilityHint(Text(store.captureScanBlockedReason ?? "List the currently available capture devices."))
    }

    @ViewBuilder
    private func deviceSelector(for kind: SourceKind) -> some View {
        switch kind {
        case .camera:
            devicePicker(
                title: "Camera",
                options: store.availableCameraDevices.map { DeviceOption(id: $0.id, name: $0.name) },
                selectedID: store.selectedCameraDeviceID,
                isEnabled: store.canSelectInputDevice,
                emptyHint: "No cameras found. Grant camera access, then Refresh."
            ) { store.selectCameraDevice(id: $0) }
        case .microphone:
            devicePicker(
                title: "Microphone",
                options: store.availableMicrophoneDevices.map { DeviceOption(id: $0.id, name: $0.name) },
                selectedID: store.selectedMicrophoneDeviceID,
                isEnabled: store.canSelectInputDevice,
                emptyHint: "No microphones found. Grant mic access, then Refresh."
            ) { store.selectMicrophoneDevice(id: $0) }
        case .screen:
            devicePicker(
                title: "Screen",
                options: store.availableScreenCaptureTargets.map { DeviceOption(id: $0.id, name: $0.title) },
                selectedID: store.selectedScreenCaptureTarget?.id,
                isEnabled: store.canEditScreenCaptureTarget,
                emptyHint: "No screens found. Grant Screen Recording, then Refresh."
            ) { id in
                if let target = store.availableScreenCaptureTargets.first(where: { $0.id == id }) {
                    store.selectScreenCaptureTarget(target)
                }
            }
        case .systemAudio:
            EmptyView()
        }
    }

    @ViewBuilder
    private func devicePicker(
        title: String,
        options: [DeviceOption],
        selectedID: String?,
        isEnabled: Bool,
        emptyHint: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        if options.isEmpty {
            Label(emptyHint, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "chevron.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(title, selection: Binding(
                    get: { selectedID ?? options.first?.id },
                    set: { newID in if let newID { onSelect(newID) } }
                )) {
                    ForEach(options) { option in
                        Text(option.name).tag(Optional(option.id))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .disabled(!isEnabled)
                .help(isEnabled ? "Choose the \(title.lowercased()) to use" : "Stop capture before changing the \(title.lowercased())")
                .accessibilityLabel(Text("\(title) device"))
            }
        }
    }
}

private struct DeviceOption: Identifiable {
    let id: String
    let name: String
}

private struct CameraEnhancementControls: View {
    @Binding var settings: CameraEnhancementSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Toggle("Mirror", isOn: mirrorBinding)
                    .toggleStyle(.checkbox)
                    .help("Mirror the local camera preview")

                Toggle("Exposure Boost", isOn: autoLightBinding)
                    .toggleStyle(.checkbox)
                    .help("Apply a simple camera brightness boost and keep auto exposure, focus, and white balance enabled")
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
                        .help("Adjust exposure boost strength")
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
