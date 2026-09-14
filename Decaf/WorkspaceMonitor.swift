import AppKit

struct WorkspaceApplication {
    let bundleIdentifier: String?
    let localizedName: String?
    let icon: NSImage?
    let processIdentifier: pid_t
    let activationPolicy: NSApplication.ActivationPolicy

    init(_ application: NSRunningApplication) {
        bundleIdentifier = application.bundleIdentifier
        localizedName = application.localizedName
        icon = application.icon
        processIdentifier = application.processIdentifier
        activationPolicy = application.activationPolicy
    }

    init(
        bundleIdentifier: String?,
        localizedName: String?,
        icon: NSImage?,
        processIdentifier: pid_t,
        activationPolicy: NSApplication.ActivationPolicy
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.icon = icon
        self.processIdentifier = processIdentifier
        self.activationPolicy = activationPolicy
    }
}

struct WorkspaceEventHandlers {
    let didLaunch: @MainActor (WorkspaceApplication) -> Void
    let didTerminate: @MainActor (WorkspaceApplication) -> Void
    let needsReconciliation: @MainActor () -> Void
}

@MainActor
protocol WorkspaceMonitoring: AnyObject {
    var runningApplications: [WorkspaceApplication] { get }

    func startMonitoring(handlers: WorkspaceEventHandlers)
}

@MainActor
final class SystemWorkspaceMonitor: WorkspaceMonitoring {
    private let workspace: NSWorkspace
    private var observationTokens: [NotificationCenter.ObservationToken] = []

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    var runningApplications: [WorkspaceApplication] {
        workspace.runningApplications.map(WorkspaceApplication.init)
    }

    func startMonitoring(handlers: WorkspaceEventHandlers) {
        guard observationTokens.isEmpty else { return }

        let center = workspace.notificationCenter
        observationTokens = [
            center.addObserver(
                of: workspace,
                for: NSWorkspace.DidLaunchApplicationMessage.self
            ) { message in
                handlers.didLaunch(WorkspaceApplication(message.application))
            },
            center.addObserver(
                of: workspace,
                for: NSWorkspace.DidTerminateApplicationMessage.self
            ) { message in
                handlers.didTerminate(WorkspaceApplication(message.application))
            },
            center.addObserver(
                of: workspace,
                for: NSWorkspace.DidWakeMessage.self
            ) { _ in
                handlers.needsReconciliation()
            },
            center.addObserver(
                of: workspace,
                for: NSWorkspace.SessionDidBecomeActiveMessage.self
            ) { _ in
                handlers.needsReconciliation()
            }
        ]
    }

    deinit {
        observationTokens.removeAll()
    }
}
