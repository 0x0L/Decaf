import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppMonitor.self) private var monitor
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("General") {
                Toggle("Keep Display On", isOn: Binding(
                    get: { monitor.keepDisplayOn },
                    set: { monitor.keepDisplayOn = $0 }
                ))

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
            }

            Section("Running Apps") {
                if monitor.visibleApps.isEmpty {
                    Text("No apps running")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monitor.visibleApps) { app in
                        HStack {
                            appLabel(app)
                            Spacer()
                            Button("Hide") {
                                monitor.setExcluded(app.id, true)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("Hidden Apps") {
                if monitor.hiddenApps.isEmpty {
                    Text("No hidden apps")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monitor.hiddenApps) { app in
                        HStack {
                            appLabel(app)
                            if !app.isRunning {
                                Text("Not running")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                            Spacer()
                            Button("Show") {
                                monitor.setExcluded(app.id, false)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 340, height: 420)
        .onAppear { NSApp.activate() }
    }

    private func appLabel(_ app: RunningApp) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(app.name)
        }
    }
}
