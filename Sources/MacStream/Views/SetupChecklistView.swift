import SwiftUI
import MacStreamCore

struct SetupChecklistView: View {
    var store: StudioStore

    var body: some View {
        if store.shouldShowSetupChecklist {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Preflight", systemImage: "checklist.checked")
                            .font(.headline)

                        Text(nextStepSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    StudioBadge(title: progressTitle, systemImage: "gauge.with.dots.needle.50percent", tint: .orange)
                }

                ProgressView(value: store.setupProgressFraction)
                    .controlSize(.small)
                    .tint(.orange)
                    .accessibilityLabel(Text("Preflight progress"))
                    .accessibilityValue(Text(progressTitle))

                VStack(spacing: 8) {
                    ForEach(store.setupChecklistItems) { item in
                        SetupChecklistRow(
                            item: item,
                            isNext: item.id == nextIncompleteItemID
                        )
                    }
                }

                primarySetupAction
                    .controlSize(.regular)
            }
            .studioCard()
        }
    }

    private var progressTitle: String {
        "\(store.completedSetupItemCount)/\(max(store.totalSetupItemCount, 1)) ready"
    }

    private var nextStepSummary: String {
        guard let nextItem = store.nextSetupChecklistItem else {
            return "All checks are ready."
        }

        return "Next: \(nextItem.title). \(nextItem.detail)"
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
                    MacStreamRelauncher.relaunch()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .frame(width: 28)
                }
                .buttonStyle(.bordered)
                .help("Reopen MacStream after granting Screen Recording")
                .accessibilityLabel(Text("Reopen MacStream"))
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
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(symbolTint)
                .frame(width: 24, height: 24)
                .background(symbolTint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))

                    StudioBadge(title: statusTitle, systemImage: nil, tint: symbolTint)
                }

                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(rowTint.opacity(isNext ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(rowTint.opacity(isNext ? 0.22 : 0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(item.title))
        .accessibilityValue(Text("\(statusTitle). \(item.detail)"))
    }

    private var statusTitle: String {
        if item.isComplete { return "Ready" }
        if isNext { return "Next" }
        return "Waiting"
    }

    private var rowTint: Color {
        if item.isComplete { return .green }
        if isNext { return .orange }
        return .secondary
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
