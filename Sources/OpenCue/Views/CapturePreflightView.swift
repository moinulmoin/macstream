import AppKit
import SwiftUI
import OpenCueCore

struct CapturePreflightView: View {
    @Bindable var store: StudioStore
    @SceneStorage("OpenCue.CapturePreflightView.showDeviceDetails") private var showDeviceDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Capture", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button {
                    store.scanCaptureDevices()
                } label: {
                    if store.isScanningCapture {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(!store.canScanCaptureDevices)
                .help(store.captureScanBlockedReason ?? "Check capture permissions")
            }

            Text(store.captureReport.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if store.requiresRelaunchForRequiredCapturePermission,
               !store.shouldShowSetupChecklist {
                Button {
                    OpenCueRelauncher.relaunch()
                } label: {
                    Label("Reopen OpenCue", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Quit and reopen OpenCue after granting Screen Recording")
            }

            if !store.availableScreenCaptureTargets.isEmpty {
                Picker("Screen target", selection: screenCaptureTarget) {
                    ForEach(store.availableScreenCaptureTargets) { target in
                        Text(target.title)
                            .tag(Optional(target))
                    }
                }
                .disabled(!store.canEditScreenCaptureTarget)
                .help(store.canEditScreenCaptureTarget ? "Choose the display or window to preview and record" : "Stop capture before changing the screen target")
            }

            if store.hasRunInitialCaptureScan {
                Label("Checked on launch", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !attentionDevices.isEmpty {
                deviceRows(for: attentionDevices)
            } else if !store.captureReport.devices.isEmpty {
                DisclosureGroup(isExpanded: $showDeviceDetails) {
                    deviceRows(for: visibleDeviceDetails)
                } label: {
                    Label("Device details", systemImage: "list.bullet.rectangle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var attentionDevices: [CaptureDeviceInfo] {
        store.captureReport.devices.filter { $0.permission != .granted }
    }

    private var visibleDeviceDetails: [CaptureDeviceInfo] {
        Array(store.captureReport.devices.prefix(6))
    }

    private func deviceRows(for devices: [CaptureDeviceInfo]) -> some View {
        VStack(spacing: 8) {
            ForEach(devices) { device in
                HStack(spacing: 8) {
                    Image(systemName: device.kind.symbolName)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(device.name)
                            .lineLimit(1)
                        if !device.detail.isEmpty {
                            Text(device.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let permissionRecoveryHint = device.permissionRecoveryHint {
                            Text(permissionRecoveryHint)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }

                    Spacer()

                    Text(device.permission.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(permissionTint(device.permission).opacity(0.14), in: Capsule())
                        .foregroundStyle(permissionTint(device.permission))

                    if canAskForPermission(device) {
                        Button("Ask") {
                            CapturePermissionActions.requestAccess(for: device.kind, store: store)
                        }
                        .buttonStyle(.borderless)
                        .help("Ask macOS for access")
                    } else if device.permission != .granted,
                              CapturePermissionActions.privacySettingsURL(for: device.kind) != nil {
                        Button {
                            CapturePermissionActions.openSettings(for: device.kind)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.borderless)
                        .help("Open privacy settings")
                    }
                }
            }
        }
    }

    private func canAskForPermission(_ device: CaptureDeviceInfo) -> Bool {
        guard device.permission == .notDetermined else { return false }
        switch device.kind {
        case .camera, .microphone:
            return true
        case .display, .window:
            return false
        }
    }

    private func permissionTint(_ permission: CapturePermissionState) -> Color {
        switch permission {
        case .granted: .green
        case .denied: .red
        case .notDetermined: .orange
        case .unknown: .secondary
        }
    }

    private var screenCaptureTarget: Binding<ScreenCaptureTarget?> {
        Binding(
            get: { store.selectedScreenCaptureTarget },
            set: { target in
                guard let target else { return }
                store.selectScreenCaptureTarget(target)
            }
        )
    }

}
