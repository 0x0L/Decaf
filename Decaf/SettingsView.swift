import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppMonitor.self) private var monitor
    @State private var loginItem = LoginItemSettings()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Keep Display On", isOn: Binding(
                    get: { monitor.keepDisplayOn },
                    set: { monitor.keepDisplayOn = $0 }
                ))

                Toggle("Launch at Login", isOn: Binding(
                    get: { loginItem.isEnabled },
                    set: { loginItem.setEnabled($0) }
                ))
                if loginItem.requiresApproval {
                    Text("Allow Decaf in Login Items to launch at login.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Login Items Settings…") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
            }

            Section("Running Apps") {
                if monitor.availableApps.isEmpty {
                    Text("No apps running")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(monitor.availableApps) { app in
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
        .onAppear {
            loginItem.refresh()
            NSApp.activate()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem.refresh()
        }
        .alert("Couldn’t Update Launch at Login", isPresented: Binding(
            get: { loginItem.errorMessage != nil },
            set: { if !$0 { loginItem.errorMessage = nil } }
        )) {
            Button("OK") { loginItem.errorMessage = nil }
        } message: {
            Text(loginItem.errorMessage ?? "")
        }
    }

    private func appLabel(_ app: AppEntry) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 16, height: 16)
            Text(app.name)
        }
    }
}
