import SwiftUI
import OpenCueCore

struct ContentView: View {
    @Bindable var store: StudioStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
        } detail: {
            StudioView(store: store)
        }
    }
}
