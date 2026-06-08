import AppKit
import SwiftUI
import MacStreamCore

struct CapturePreflightView: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Label("Capture", systemImage: "checklist")
                        .font(.headline)

                    Text(store.captureReport.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

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
                .accessibilityLabel(Text(store.isScanningCapture ? "Checking capture" : "Check capture"))
                .accessibilityHint(Text(store.captureScanBlockedReason ?? "Refresh camera, microphone, and screen permissions."))
            }


            if store.requiresRelaunchForRequiredCapturePermission,
               !store.shouldShowSetupChecklist {
                Button {
                    MacStreamRelauncher.relaunch()
                } label: {
                    Label("Reopen MacStream", systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Quit and reopen MacStream after granting Screen Recording")
            }

            if store.hasRunInitialCaptureScan {
                Label("Checked on launch", systemImage: "checkmark.seal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !attentionDevices.isEmpty {
                deviceRows(for: attentionDevices)
            }
        }
        .studioCard()
    }

    private var attentionDevices: [CaptureDeviceInfo] {
        store.captureReport.devices.filter { $0.permission != .granted }
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
                        .accessibilityLabel(Text("Open \(device.kind.title) privacy settings"))
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

}
