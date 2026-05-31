import SwiftUI
import OpenCueCore

struct StudioNavigationPanelView: View {
    @Bindable var store: StudioStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Scenes", systemImage: "rectangle.3.group")
                .font(.headline)

            VStack(spacing: 6) {
                ForEach(store.scenes) { scene in
                    let blocker = store.sceneSelectionBlockedReason(for: scene)
                    let canSelectScene = store.canSelectScene(scene)

                    Button {
                        store.selectScene(scene)
                    } label: {
                        SceneChoiceRow(
                            scene: scene,
                            isSelected: scene.id == store.selectedSceneID,
                            detail: blocker ?? scene.subtitle
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSelectScene)
                    .help(blocker ?? scene.subtitle)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SceneChoiceRow: View {
    var scene: StudioScene
    var isSelected: Bool
    var detail: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: scene.kind.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(scene.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    private var rowBackground: some ShapeStyle {
        isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.secondary.opacity(0.08))
    }
}
