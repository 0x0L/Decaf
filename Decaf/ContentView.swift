import ServiceManagement
import SwiftUI

struct ContentView: View {
    @Environment(AppMonitor.self) private var monitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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

        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            }

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
