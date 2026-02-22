import SwiftUI

@main
struct DecafApp: App {
    @State private var appMonitor = AppMonitor()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environment(appMonitor)
        } label: {
            Image(systemName: appMonitor.isCaffeinateRunning
                  ? "cup.and.saucer.fill"
                  : "cup.and.saucer")
                .contentTransition(.symbolEffect(.replace))
        }
    }
}
