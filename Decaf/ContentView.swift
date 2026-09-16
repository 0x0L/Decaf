import SwiftUI

struct ContentView: View {
    @Environment(AppMonitor.self) private var monitor

    private var runningApps: [AppEntry] {
        monitor.menuApps.filter(\.isRunning)
    }

    private var stoppedApps: [AppEntry] {
        monitor.menuApps.filter { !$0.isRunning }
    }

    var body: some View {
        if runningApps.isEmpty && stoppedApps.isEmpty {
            Text("No apps running")
                .foregroundStyle(.secondary)
        }

        ForEach(runningApps) { app in
            appToggle(app)
        }

        if !stoppedApps.isEmpty {
            Divider()

            Text("Not running")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(stoppedApps) { app in
                appToggle(app)
            }
        }

        Divider()

        SettingsLink {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                Text("Settings\u{2026}")
            }
        }

        Button {
            NSApp.terminate(nil)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "power")
                Text("Quit Decaf")
            }
        }
    }

    private func appToggle(_ app: AppEntry) -> some View {
        Toggle(isOn: Binding(
            get: { monitor.isEnabled(app.id) },
            set: { monitor.setEnabled(app.id, $0) }
        )) {
            Label {
                Text(app.name)
            } icon: {
                Image(nsImage: app.icon)
                    .resizable()
                    .renderingMode(.original)
                    .frame(width: 16, height: 16)
            }
        }
    }
}
