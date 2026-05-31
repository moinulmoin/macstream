import SwiftUI
import OpenCueCore

struct ContentView: View {
    @Bindable var store: StudioStore

    var body: some View {
        StudioView(store: store)
    }
}
