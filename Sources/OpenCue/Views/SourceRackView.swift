import SwiftUI
import OpenCueCore

struct SourceRackView: View {
    @Bindable var store: StudioStore
    @SceneStorage("OpenCue.SourceRackView.showMoreSources") private var showMoreSources = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Sources", systemImage: "slider.horizontal.3")
                .font(.headline)

            sourceRows(for: primarySources)

            if !secondarySources.isEmpty {
                DisclosureGroup(isExpanded: $showMoreSources) {
                    sourceRows(for: secondarySources)
                } label: {
                    Label("More sources", systemImage: "ellipsis.circle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(source.title, systemImage: source.kind.symbolName)
                    Spacer()
                    Button {
                        store.toggleSource(source)
                    } label: {
                        Image(systemName: source.isEnabled ? "checkmark.circle.fill" : "circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(!store.canToggleSource(source))
                    .help(sourceToggleHelp(for: source))
                }

                if source.kind.supportsLevelControl {
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
                }
            }
            .padding(.vertical, 4)
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
