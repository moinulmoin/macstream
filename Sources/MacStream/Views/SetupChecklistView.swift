import SwiftUI
import MacStreamCore

struct SetupChecklistView: View {
    var store: StudioStore

    var body: some View {
        if store.shouldShowSetupChecklist {
            VStack(alignment: .leading, spacing: StudioMetrics.md) {
                StudioPanelHeader(
                    title: "Preflight",
                    systemImage: "checklist.checked",
                    subtitle: nextStepSummary,
                    tint: StudioPalette.warning
                ) {
                    StudioBadge(
                        title: progressTitle,
                        systemImage: "gauge.with.dots.needle.50percent",
                        tint: StudioPalette.warning
                    )
                }

                ProgressView(value: store.setupProgressFraction)
                    .controlSize(.small)
                    .tint(StudioPalette.warning)
                    .accessibilityLabel(Text("Preflight progress"))
                    .accessibilityValue(Text(progressTitle))

                VStack(spacing: StudioMetrics.sm) {
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
                Label("Use Screen + Webcam", systemImage: "rectangle.inset.filled.and.person.filled")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .help("Select the default screen and webcam scene")
        case .some(.capture), .some(.destination), .some(.sources):
            EmptyView()
        case nil:
            EmptyView()
        }
    }

    private var nextIncompleteItemID: SetupChecklistItemID? {
        store.nextSetupChecklistItem?.id
    }

}

private struct SetupChecklistRow: View {
    var item: SetupChecklistItem
    var isNext: Bool

    var body: some View {
        HStack(alignment: .top, spacing: StudioMetrics.md) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(symbolTint)
                .frame(width: 24, height: 24)
                .background(symbolTint.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: StudioMetrics.xs) {
                HStack(spacing: StudioMetrics.sm) {
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
        .padding(StudioMetrics.md)
        .background(rowTint.opacity(isNext ? 0.12 : 0.06), in: RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: StudioMetrics.controlRadius, style: .continuous)
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
        if item.isComplete { return StudioPalette.success }
        if isNext { return StudioPalette.warning }
        return .secondary
    }

    private var symbolName: String {
        if item.isComplete { return "checkmark.circle.fill" }
        if isNext { return "arrow.right.circle.fill" }
        return "circle"
    }

    private var symbolTint: Color {
        if item.isComplete { return StudioPalette.success }
        if isNext { return StudioPalette.warning }
        return .secondary
    }
}
