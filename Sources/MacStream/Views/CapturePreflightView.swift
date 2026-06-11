import AppKit
import SwiftUI
import MacStreamCore

struct CapturePreflightView: View {
    var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StudioPanelHeader(
                title: "Capture",
                systemImage: "checklist",
                subtitle: store.captureReport.summary
            ) {
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

            let rows = CapturePermissionRow.rows(from: store.captureReport.devices)
            if !rows.isEmpty {
                permissionRows(rows)
            }
        }
        .studioCard()
    }

    private func permissionRows(_ rows: [CapturePermissionRow]) -> some View {
        VStack(spacing: 10) {
            ForEach(rows) { row in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: row.kind.symbolName)
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)

                        Text(row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if let recoveryHint = row.recoveryHint {
                            Text(recoveryHint)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 8)

                    permissionAction(for: row)
                }
            }
        }
    }

    @ViewBuilder
    private func permissionAction(for row: CapturePermissionRow) -> some View {
        if canAskForPermission(row) {
            Button {
                CapturePermissionActions.requestAccess(for: row.requestKind, store: store)
            } label: {
                Text("Ask")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(.orange)
            .help("Ask macOS for \(row.title.lowercased())")
        } else if row.permission != .granted,
                  CapturePermissionActions.privacySettingsURL(for: row.requestKind) != nil {
            Button {
                CapturePermissionActions.openSettings(for: row.requestKind)
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Open \(row.title.lowercased()) settings")
            .accessibilityLabel(Text("Open \(row.title) settings"))
        } else {
            Text(row.permission.title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(permissionTint(row.permission).opacity(0.14), in: Capsule())
                .foregroundStyle(permissionTint(row.permission))
        }
    }

    private func canAskForPermission(_ row: CapturePermissionRow) -> Bool {
        guard row.permission == .notDetermined else { return false }
        switch row.requestKind {
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

private struct CapturePermissionRow: Identifiable {
    var id: String
    var kind: CaptureDeviceKind
    var requestKind: CaptureDeviceKind
    var title: String
    var detail: String
    var permission: CapturePermissionState
    var recoveryHint: String?

    static func rows(from devices: [CaptureDeviceInfo]) -> [CapturePermissionRow] {
        [
            row(
                id: "camera",
                kind: .camera,
                requestKind: .camera,
                title: "Camera Access",
                devices: devices.filter { $0.kind == .camera && $0.permission != .granted },
                pluralName: "cameras"
            ),
            row(
                id: "microphone",
                kind: .microphone,
                requestKind: .microphone,
                title: "Microphone Access",
                devices: devices.filter { $0.kind == .microphone && $0.permission != .granted },
                pluralName: "microphones"
            ),
            row(
                id: "screen",
                kind: .display,
                requestKind: .display,
                title: "Screen Recording",
                devices: devices.filter {
                    ($0.kind == .display || $0.kind == .window) && $0.permission != .granted
                },
                pluralName: "screen targets",
                fixedDetail: "Required for display and window capture."
            )
        ]
        .compactMap { $0 }
    }

    private static func row(
        id: String,
        kind: CaptureDeviceKind,
        requestKind: CaptureDeviceKind,
        title: String,
        devices: [CaptureDeviceInfo],
        pluralName: String,
        fixedDetail: String? = nil
    ) -> CapturePermissionRow? {
        guard !devices.isEmpty else { return nil }
        return CapturePermissionRow(
            id: id,
            kind: kind,
            requestKind: requestKind,
            title: title,
            detail: fixedDetail ?? detail(for: devices, pluralName: pluralName),
            permission: combinedPermission(for: devices),
            recoveryHint: devices.compactMap(\.permissionRecoveryHint).first
        )
    }

    private static func detail(for devices: [CaptureDeviceInfo], pluralName: String) -> String {
        guard devices.count > 1 else {
            let device = devices[0]
            return device.detail.isEmpty ? device.name : "\(device.name) · \(device.detail)"
        }

        let names = devices.prefix(2).map(\.name).joined(separator: ", ")
        let remainder = devices.count - 2
        if remainder > 0 {
            return "\(devices.count) \(pluralName): \(names), +\(remainder) more"
        }
        return "\(devices.count) \(pluralName): \(names)"
    }

    private static func combinedPermission(for devices: [CaptureDeviceInfo]) -> CapturePermissionState {
        if devices.contains(where: { $0.permission == .denied }) { return .denied }
        if devices.contains(where: { $0.permission == .notDetermined }) { return .notDetermined }
        if devices.contains(where: { $0.permission == .unknown }) { return .unknown }
        return .granted
    }
}
