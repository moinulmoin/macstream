import SwiftUI
import MacStreamCore

struct ContentView: View {
    var store: StudioStore

    var body: some View {
        StudioView(store: store)
            .preferredColorScheme(.dark)
            .tint(StudioPalette.accent)
    }
}
