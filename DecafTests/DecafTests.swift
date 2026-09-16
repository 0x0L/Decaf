import AppKit
import Foundation
import Testing
@testable import Decaf

@Suite(.serialized)
@MainActor
struct AppMonitorTests {
    @Test
    func `Initial snapshot includes only regular applications`() {
        let workspace = FakeWorkspaceMonitor(runningApplications: [
            makeApplication(id: "com.example.beta", name: "Beta", pid: 2),
            makeApplication(id: "com.example.alpha", name: "Alpha", pid: 1),
            makeApplication(
                id: "com.example.agent",
                name: "Agent",
                pid: 3,
                activationPolicy: .accessory
            )
        ])
        let monitor = makeMonitor(workspace: workspace)

        #expect(monitor.visibleApps.map(\.name) == ["Alpha", "Beta"])
        #expect(monitor.apps.map(\.id) == [
            "com.example.alpha",
            "com.example.beta"
        ])
    }

    @Test
    func `App remains running until its final process terminates`() {
        let workspace = FakeWorkspaceMonitor()
        let monitor = makeMonitor(workspace: workspace)
        let first = makeApplication(id: "com.example.editor", name: "Editor", pid: 10)
        let second = makeApplication(id: "com.example.editor", name: "Editor", pid: 11)

        workspace.sendLaunch(first)
        workspace.sendLaunch(second)
        workspace.sendTermination(first)

        #expect(monitor.apps.count == 1)
        #expect(monitor.apps.first?.isRunning == true)

        workspace.sendTermination(second)

        #expect(monitor.apps.isEmpty)
    }

    @Test
    func `Enabled app remains watched after termination`() {
        let workspace = FakeWorkspaceMonitor()
        let monitor = makeMonitor(workspace: workspace)
        let application = makeApplication(id: "com.example.editor", name: "Editor", pid: 10)

        workspace.sendLaunch(application)
        monitor.setEnabled("com.example.editor", true)
        workspace.sendTermination(application)

        #expect(monitor.apps.count == 1)
        #expect(monitor.apps.first?.name == "Editor")
        #expect(monitor.apps.first?.isRunning == false)
    }

    @Test
    func `Caffeinate follows enabled running applications`() {
        let workspace = FakeWorkspaceMonitor()
        let caffeinate = FakeCaffeinateManager()
        let monitor = makeMonitor(workspace: workspace, caffeinate: caffeinate)
        let application = makeApplication(id: "com.example.editor", name: "Editor", pid: 10)

        workspace.sendLaunch(application)
        monitor.setEnabled("com.example.editor", true)

        #expect(caffeinate.isRunning)
        #expect(monitor.isCaffeinateRunning)

        workspace.sendTermination(application)

        #expect(!caffeinate.isRunning)
        #expect(!monitor.isCaffeinateRunning)
        #expect(caffeinate.requests.map(\.shouldRun) == [false, true, false])
    }

    @Test
    func `Exit with unavailable identity stops caffeinate immediately`() {
        let application = makeApplication(id: "com.example.editor", name: "Editor", pid: 10)
        let workspace = FakeWorkspaceMonitor(runningApplications: [application])
        let caffeinate = FakeCaffeinateManager()
        let monitor = makeMonitor(workspace: workspace, caffeinate: caffeinate)
        monitor.setEnabled("com.example.editor", true)
        #expect(monitor.isCaffeinateRunning)

        workspace.runningApplications = []
        workspace.sendTermination(WorkspaceApplication(
            bundleIdentifier: nil,
            localizedName: nil,
            icon: nil,
            processIdentifier: -1,
            activationPolicy: .prohibited
        ))

        #expect(monitor.apps.first?.isRunning == false)
        #expect(monitor.visibleApps.isEmpty)
        #expect(monitor.isEnabled("com.example.editor"))
        #expect(!monitor.isCaffeinateRunning)
        #expect(!caffeinate.isRunning)
        #expect(workspace.snapshotReadCount == 2)
    }

    @Test
    func `Exit with invalid PID preserves another running instance`() {
        let first = makeApplication(id: "com.example.editor", name: "Editor", pid: 10)
        let second = makeApplication(id: "com.example.editor", name: "Editor", pid: 11)
        let workspace = FakeWorkspaceMonitor(runningApplications: [first, second])
        let caffeinate = FakeCaffeinateManager()
        let monitor = makeMonitor(workspace: workspace, caffeinate: caffeinate)
        monitor.setEnabled("com.example.editor", true)

        workspace.runningApplications = [second]
        workspace.sendTermination(makeApplication(id: "com.example.editor", name: "Editor", pid: -1))

        #expect(monitor.apps.first?.isRunning == true)
        #expect(caffeinate.isRunning)

        workspace.runningApplications = []
        workspace.sendTermination(makeApplication(id: "com.example.editor", name: "Editor", pid: -1))

        #expect(monitor.apps.first?.isRunning == false)
        #expect(!caffeinate.isRunning)
    }

    @Test
    func `Quitting UI stops caffeinate even when the process stays alive`() {
        let application = makeApplication(id: "com.apple.iBooksX", name: "Books", pid: 10)
        let workspace = FakeWorkspaceMonitor(runningApplications: [application])
        let caffeinate = FakeCaffeinateManager()
        let monitor = makeMonitor(workspace: workspace, caffeinate: caffeinate)
        monitor.setEnabled(application.bundleIdentifier!, true)
        #expect(monitor.isCaffeinateRunning)

        // Books keeps its PID but becomes prohibited after quitting its UI.
        workspace.runningApplications = [makeApplication(
            id: "com.apple.iBooksX", name: "Books", pid: 10, activationPolicy: .prohibited
        )]
        workspace.requestReconciliation()

        #expect(monitor.apps.first?.isRunning == false)
        #expect(monitor.visibleApps.isEmpty)
        #expect(!caffeinate.isRunning)
        #expect(!monitor.isCaffeinateRunning)

        // Reopening the UI may reuse the same process without a launch event.
        workspace.runningApplications = [application]
        workspace.requestReconciliation()

        #expect(monitor.apps.first?.isRunning == true)
        #expect(caffeinate.isRunning)
        #expect(monitor.isCaffeinateRunning)
    }

    @Test
    func `Timer detects policy changes without workspace events`() async throws {
        let application = makeApplication(id: "com.apple.iBooksX", name: "Books", pid: 10)
        let workspace = FakeWorkspaceMonitor(runningApplications: [application])
        let caffeinate = FakeCaffeinateManager()
        let monitor = makeMonitor(
            workspace: workspace, caffeinate: caffeinate, reconciliationInterval: 0.02
        )
        monitor.setEnabled("com.apple.iBooksX", true)
        workspace.runningApplications = [makeApplication(
            id: "com.apple.iBooksX", name: "Books", pid: 10, activationPolicy: .prohibited
        )]

        for _ in 0..<100 where monitor.isCaffeinateRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!monitor.isCaffeinateRunning)
        #expect(monitor.apps.first?.isRunning == false)

        workspace.runningApplications = [application]
        for _ in 0..<100 where !monitor.isCaffeinateRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.isCaffeinateRunning)
        #expect(monitor.apps.first?.isRunning == true)
    }

    @Test
    func `Excluding an app moves it out of the menu immediately`() {
        let workspace = FakeWorkspaceMonitor(runningApplications: [
            makeApplication(id: "com.example.editor", name: "Editor", pid: 10)
        ])
        let monitor = makeMonitor(workspace: workspace)
        #expect(workspace.snapshotReadCount == 1)

        monitor.setExcluded("com.example.editor", true)

        #expect(workspace.snapshotReadCount == 1)
        #expect(monitor.apps.isEmpty)
        #expect(monitor.visibleApps.isEmpty)
        #expect(monitor.hiddenApps.map(\.id) == ["com.example.editor"])
    }

    @Test
    func `Reconciliation recovers a missed launch event`() {
        let workspace = FakeWorkspaceMonitor()
        let monitor = makeMonitor(workspace: workspace)

        workspace.runningApplications = [
            makeApplication(id: "com.example.editor", name: "Editor", pid: 10)
        ]
        workspace.requestReconciliation()

        #expect(monitor.apps.map(\.id) == ["com.example.editor"])
        #expect(monitor.apps.first?.isRunning == true)
    }

    private func makeMonitor(workspace: FakeWorkspaceMonitor) -> AppMonitor {
        makeMonitor(
            workspace: workspace,
            caffeinate: FakeCaffeinateManager()
        )
    }

    private func makeMonitor(
        workspace: FakeWorkspaceMonitor,
        caffeinate: FakeCaffeinateManager,
        reconciliationInterval: TimeInterval = 0
    ) -> AppMonitor {
        let suiteName = "AppMonitorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        return AppMonitor(
            workspaceMonitor: workspace,
            caffeinateManager: caffeinate,
            defaults: defaults,
            reconciliationInterval: reconciliationInterval
        )
    }

    private func makeApplication(
        id: String,
        name: String,
        pid: pid_t,
        activationPolicy: NSApplication.ActivationPolicy = .regular
    ) -> WorkspaceApplication {
        WorkspaceApplication(
            bundleIdentifier: id,
            localizedName: name,
            icon: NSImage(),
            processIdentifier: pid,
            activationPolicy: activationPolicy
        )
    }
}

@MainActor
private final class FakeWorkspaceMonitor: WorkspaceMonitoring {
    var runningApplications: [WorkspaceApplication] {
        get {
            snapshotReadCount += 1
            return storedRunningApplications
        }
        set {
            storedRunningApplications = newValue
        }
    }
    private(set) var snapshotReadCount = 0
    private var storedRunningApplications: [WorkspaceApplication]
    private var handlers: WorkspaceEventHandlers?

    init(runningApplications: [WorkspaceApplication] = []) {
        storedRunningApplications = runningApplications
    }

    func startMonitoring(handlers: WorkspaceEventHandlers) {
        self.handlers = handlers
    }

    func stopMonitoring() {
        handlers = nil
    }

    func sendLaunch(_ application: WorkspaceApplication) {
        storedRunningApplications.append(application)
        handlers?.didLaunch(application)
    }

    func sendTermination(_ application: WorkspaceApplication) {
        storedRunningApplications.removeAll {
            $0.processIdentifier == application.processIdentifier
        }
        handlers?.didTerminate(application)
    }

    func requestReconciliation() {
        handlers?.needsReconciliation()
    }
}

@MainActor
private final class FakeCaffeinateManager: CaffeinateManaging {
    struct Request {
        let shouldRun: Bool
        let keepDisplayOn: Bool
    }

    private(set) var isRunning = false
    private(set) var requests: [Request] = []
    private(set) var restartRequests: [Bool] = []

    func update(shouldRun: Bool, keepDisplayOn: Bool) {
        requests.append(Request(
            shouldRun: shouldRun,
            keepDisplayOn: keepDisplayOn
        ))
        isRunning = shouldRun
    }

    func restart(keepDisplayOn: Bool) {
        restartRequests.append(keepDisplayOn)
        isRunning = true
    }

    func stop() {
        isRunning = false
    }
}
