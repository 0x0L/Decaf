import SwiftUI

struct ContentView: View {
    @Environment(AppMonitor.self) private var monitor

    private var runningApps: [RunningApp] {
        monitor.apps.filter(\.isRunning)
    }

    private var watchedApps: [RunningApp] {
        monitor.apps.filter { !$0.isRunning }
    }

    var body: some View {
        ForEach(runningApps) { app in
            appToggle(app)
        }

        if !watchedApps.isEmpty {
            Divider()

            Text("Not Running")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(watchedApps) { app in
                appToggle(app)
            }
        }

        Divider()

        Button("Quit Decaf") {
            NSApp.terminate(nil)
        }
    }

    private func appToggle(_ app: RunningApp) -> some View {
        Toggle(isOn: Binding(
            get: { monitor.isEnabled(app.id) },
            set: { monitor.setEnabled(app.id, $0) }
        )) {
            HStack(spacing: 6) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(app.name)
            }
        }
    }
}
