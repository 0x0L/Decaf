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
                ? "mug.fill"
                : "mug")
                .contentTransition(.symbolEffect(.replace))
        }

        Settings {
            SettingsView()
                .environment(appMonitor)
        }
    }
}
