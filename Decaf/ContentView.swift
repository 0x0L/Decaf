import SwiftUI

struct ContentView: View {
    @Environment(AppMonitor.self) private var monitor

    var body: some View {
        ForEach(monitor.apps) { app in
            Toggle(isOn: Binding(
                get: { monitor.isEnabled(app.id) },
                set: { monitor.setEnabled(app.id, $0) }
            )) {
                HStack(spacing: 6) {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(app.name)
                    if !app.isRunning {
                        Text("(not running)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        Divider()

        Button("Quit Decaf") {
            NSApp.terminate(nil)
        }
    }
}
