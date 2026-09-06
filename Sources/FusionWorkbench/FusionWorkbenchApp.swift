import SwiftUI

@main
struct FusionWorkbenchApp: App {
    @StateObject private var store = FusionStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 1040, minHeight: 700)
        }
        .defaultSize(width: 1420, height: 860)
        .windowStyle(.hiddenTitleBar)
    }
}
