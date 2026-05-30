import SwiftUI
import OpenCueCore

struct SidebarView: View {
    @Bindable var store: StudioStore

    var body: some View {
        List(selection: sceneSelection) {
            Section("Setup") {
                SidebarSetupStatusRow(
                    completedItemCount: store.completedSetupItemCount,
                    totalItemCount: store.totalSetupItemCount,
                    progressFraction: store.setupProgressFraction,
                    nextItem: store.nextSetupChecklistItem
                )
            }

            Section("Scenes") {
                ForEach(store.scenes) { scene in
                    let sceneSelectionBlocker = store.sceneSelectionBlockedReason(for: scene)
                    let canSelectScene = store.canSelectScene(scene)

                    SceneRow(scene: scene, blocker: sceneSelectionBlocker)
                        .tag(scene.id)
                        .disabled(!canSelectScene)
                        .help(sceneSelectionBlocker ?? scene.subtitle)
                }
            }

            Section("Sources") {
                ForEach(store.sources) { source in
                    SourceStatusRow(
                        source: source,
                        role: store.setupRole(for: source.kind)
                    )
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("OpenCue")
    }

    private var sceneSelection: Binding<StudioScene.ID?> {
        Binding(
            get: { store.selectedSceneID },
            set: { sceneID in
                guard let sceneID,
                      sceneID != store.selectedSceneID,
                      let scene = store.scenes.first(where: { $0.id == sceneID })
                else { return }

                store.selectScene(scene)
            }
        )
    }
}

private struct SidebarSetupStatusRow: View {
    var completedItemCount: Int
    var totalItemCount: Int
    var progressFraction: Double
    var nextItem: SetupChecklistItem?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: nextItem == nil ? "checkmark.seal.fill" : "checklist")
                .foregroundStyle(nextItem == nil ? .green : .orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(statusTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(progressTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: progressFraction)
                    .controlSize(.small)
                    .tint(nextItem == nil ? .green : .orange)

                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private var statusTitle: String {
        guard let nextItem else { return "Ready to start" }
        return "Next: \(nextItem.title)"
    }

    private var statusDetail: String {
        nextItem?.detail ?? "Scene, capture, destination, and sources are ready."
    }

    private var progressTitle: String {
        "\(completedItemCount)/\(max(totalItemCount, 1))"
    }
}

private struct SceneRow: View {
    var scene: StudioScene
    var blocker: String?

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(scene.title)
                Text(blocker ?? scene.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: scene.kind.symbolName)
        }
        .padding(.vertical, 3)
    }
}

private struct SourceStatusRow: View {
    var source: StudioSource
    var role: SourceSetupRole

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(source.title)
                        .lineLimit(1)
                    Spacer()
                    Circle()
                        .fill(statusTint)
                        .frame(width: 7, height: 7)
                }

                Text("\(role.title) - \(sourceStateTitle)")
                    .font(.caption)
                    .foregroundStyle(roleTint)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: source.kind.symbolName)
        }
        .foregroundStyle(source.isEnabled ? .primary : .secondary)
    }

    private var statusTint: Color {
        guard source.isEnabled else { return .secondary }

        if isMuted {
            switch role {
            case .required, .recommended:
                return .orange
            case .optional, .unused:
                return .secondary
            }
        }

        return .green
    }

    private var roleTint: Color {
        switch role {
        case .required:
            isUsable ? .green : .orange
        case .recommended:
            isUsable ? .secondary : .orange
        case .optional, .unused:
            .secondary
        }
    }

    private var sourceStateTitle: String {
        if !source.isEnabled { return "Off" }
        if isMuted { return "Muted" }
        return "On"
    }

    private var isUsable: Bool {
        source.isEnabled && !isMuted
    }

    private var isMuted: Bool {
        source.kind.supportsLevelControl && source.level <= 0
    }
}
