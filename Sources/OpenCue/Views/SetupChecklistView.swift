import SwiftUI
import OpenCueCore

struct SetupChecklistView: View {
    @Bindable var store: StudioStore

    var body: some View {
        if store.shouldShowSetupChecklist {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Get Started", systemImage: "checklist.checked")
                        .font(.headline)
                    Spacer()
                    Text(progressTitle)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: store.setupProgressFraction)
                    .controlSize(.small)
                    .tint(.orange)

                VStack(spacing: 8) {
                    ForEach(store.setupChecklistItems) { item in
                        SetupChecklistRow(
                            item: item,
                            isNext: item.id == nextIncompleteItemID
                        )
                    }
                }

                primarySetupAction
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
    }

    private var progressTitle: String {
        "\(store.completedSetupItemCount)/\(max(store.totalSetupItemCount, 1)) ready"
    }

    @ViewBuilder
    private var primarySetupAction: some View {
        switch nextIncompleteItemID {
        case .some(.scene):
            Button {
                store.selectRecommendedStartingScene()
            } label: {
                Label("Use Screen + Face", systemImage: "rectangle.inset.filled.and.person.filled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .help("Select the default screen and camera scene")
        case .some(.capture):
            captureSetupAction
        case .some(.destination):
            Button {
                store.setDestinationMode(.preview)
            } label: {
                Label("Use Preview", systemImage: "play.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .help("Use a local preview session before adding RTMP")
        case .some(.sources):
            Button {
                store.enableRecommendedSources()
            } label: {
                Label("Fix Needed Sources", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .help("Enable or raise the camera, screen, and microphone sources needed for the selected scene")
        case nil:
            EmptyView()
        }
    }

    private var nextIncompleteItemID: SetupChecklistItemID? {
        store.nextSetupChecklistItem?.id
    }

    @ViewBuilder
    private var captureSetupAction: some View {
        if store.isScanningCapture {
            Button {
            } label: {
                Label("Checking Capture", systemImage: "hourglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        } else if let promptableKind = promptableMissingCaptureKind {
            Button {
                CapturePermissionActions.requestAccess(for: promptableKind, store: store)
            } label: {
                Label("Ask \(promptableKind.title)", systemImage: promptableKind.symbolName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .help("Ask macOS for \(promptableKind.title.lowercased()) access")
        } else if missingScreenCaptureAccess {
            HStack(spacing: 8) {
                Button {
                    CapturePermissionActions.openSettings(for: .display)
                } label: {
                    Label("Open Screen Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .help("Grant Screen Recording in System Settings")

                Button {
                    OpenCueRelauncher.relaunch()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .help("Reopen OpenCue after granting Screen Recording")
            }
        } else if let blockedKind = blockedMissingCaptureKind {
            Button {
                CapturePermissionActions.openSettings(for: blockedKind)
            } label: {
                Label("Open \(blockedKind.title) Settings", systemImage: "gearshape")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .help("Grant \(blockedKind.title.lowercased()) access in System Settings")
        } else if let missingDeviceKind = missingRequiredDeviceKind {
            Button {
                store.scanCaptureDevices()
            } label: {
                Label("Check \(missingDeviceKind.title)", systemImage: missingDeviceKind.symbolName)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canScanCaptureDevices)
            .help("Connect \(missingDeviceKind.title.lowercased()) hardware, then check capture again")
        } else {
            Button {
                store.scanCaptureDevices()
            } label: {
                Label("Check Capture", systemImage: "checklist")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canScanCaptureDevices)
            .help("Check camera, microphone, and screen permissions")
        }
    }

    private var promptableMissingCaptureKind: CaptureDeviceKind? {
        store.promptableRequiredCapturePermissionKinds.first
    }

    private var blockedMissingCaptureKind: CaptureDeviceKind? {
        store.blockedRequiredCapturePermissionKinds.first
    }

    private var missingRequiredDeviceKind: CaptureDeviceKind? {
        store.missingRequiredCaptureDeviceKinds.first
    }

    private var missingScreenCaptureAccess: Bool {
        store.missingRequiredCapturePermissionKinds.contains { $0.requiresRestartAfterPermissionGrant }
    }
}

private struct SetupChecklistRow: View {
    var item: SetupChecklistItem
    var isNext: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: symbolName)
                .foregroundStyle(symbolTint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                    if isNext {
                        Text("Next")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.16), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isNext ? 8 : 0)
        .background {
            if isNext {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.orange.opacity(0.08))
            }
        }
        .overlay {
            if isNext {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.orange.opacity(0.16), lineWidth: 1)
            }
        }
    }

    private var symbolName: String {
        if item.isComplete { return "checkmark.circle.fill" }
        if isNext { return "arrow.right.circle.fill" }
        return "circle"
    }

    private var symbolTint: Color {
        if item.isComplete { return .green }
        if isNext { return .orange }
        return .secondary
    }
}
