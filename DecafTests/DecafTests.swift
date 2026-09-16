import AppKit
import Foundation
import Observation
import Testing
@testable import Decaf

@Suite(.serialized)
@MainActor
struct AppMonitorTests {
    private let preferences = TestPreferences()

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

        #expect(monitor.availableApps.map(\.name) == ["Alpha", "Beta"])
        #expect(monitor.menuApps.map(\.id) == [
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

        #expect(monitor.menuApps.count == 1)
        #expect(monitor.menuApps.first?.isRunning == true)

        workspace.sendTermination(second)

        #expect(monitor.menuApps.isEmpty)
    }

    @Test
    func `Enabled app remains watched after termination`() {
        let workspace = FakeWorkspaceMonitor()
        let monitor = makeMonitor(workspace: workspace)
        let application = makeApplication(id: "com.example.editor", name: "Editor", pid: 10)

        workspace.sendLaunch(application)
        monitor.setEnabled("com.example.editor", true)
        workspace.sendTermination(application)

        #expect(monitor.menuApps.count == 1)
        #expect(monitor.menuApps.first?.name == "Editor")
        #expect(monitor.menuApps.first?.isRunning == false)
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

        #expect(monitor.menuApps.first?.isRunning == false)
        #expect(monitor.availableApps.isEmpty)
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

        #expect(monitor.menuApps.first?.isRunning == true)
        #expect(caffeinate.isRunning)

        workspace.runningApplications = []
        workspace.sendTermination(makeApplication(id: "com.example.editor", name: "Editor", pid: -1))

        #expect(monitor.menuApps.first?.isRunning == false)
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

        #expect(monitor.menuApps.first?.isRunning == false)
        #expect(monitor.availableApps.isEmpty)
        #expect(!caffeinate.isRunning)
        #expect(!monitor.isCaffeinateRunning)

        // Reopening the UI may reuse the same process without a launch event.
        workspace.runningApplications = [application]
        workspace.requestReconciliation()

        #expect(monitor.menuApps.first?.isRunning == true)
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
        #expect(monitor.menuApps.first?.isRunning == false)

        workspace.runningApplications = [application]
        for _ in 0..<100 where !monitor.isCaffeinateRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(monitor.isCaffeinateRunning)
        #expect(monitor.menuApps.first?.isRunning == true)
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
        #expect(monitor.menuApps.isEmpty)
        #expect(monitor.availableApps.isEmpty)
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

        #expect(monitor.menuApps.map(\.id) == ["com.example.editor"])
        #expect(monitor.menuApps.first?.isRunning == true)
    }

    @Test
    func `Selections hidden metadata and display preference survive restart`() {
        let editor = makeApplication(id: "editor", name: "Editor", pid: 1)
        let reader = makeApplication(id: "reader", name: "Reader", pid: 2)
        let workspace = FakeWorkspaceMonitor(runningApplications: [editor, reader])
        let monitor = makeMonitor(workspace: workspace)
        monitor.setEnabled("editor", true)
        monitor.setEnabled("reader", true)
        monitor.setExcluded("reader", true)
        monitor.keepDisplayOn = true

        let restored = makeMonitor(workspace: FakeWorkspaceMonitor())
        #expect(restored.keepDisplayOn)
        #expect(restored.isEnabled("editor"))
        #expect(restored.isEnabled("reader"))
        #expect(restored.menuApps.map(\.name) == ["Editor"])
        #expect(restored.hiddenApps.map(\.name) == ["Reader"])
        #expect(restored.menuApps.allSatisfy { !$0.isRunning })
        #expect(restored.hiddenApps.allSatisfy { !$0.isRunning })
        #expect(!restored.isCaffeinateRunning)

        restored.setExcluded("reader", false)
        #expect(restored.menuApps.map(\.name) == ["Editor", "Reader"])
    }

    @Test
    func `Live metadata replaces saved metadata and remains cached`() throws {
        let saved = StoredApp(id: "editor", name: "Old Editor", iconData: Data())
        preferences.defaults.set(try JSONEncoder().encode(["editor": saved]), forKey: "enabledApps")
        let workspace = FakeWorkspaceMonitor()
        let monitor = makeMonitor(workspace: workspace)
        let savedIcon = try #require(monitor.menuApps.first?.icon)
        let live = makeApplication(id: "editor", name: "Editor", pid: 1)

        workspace.sendLaunch(live)
        #expect(monitor.menuApps.first?.name == "Editor")
        #expect(monitor.menuApps.first?.icon === live.icon)
        #expect(monitor.menuApps.first?.icon !== savedIcon)
        #expect(monitor.enabledApps["editor"]?.name == "Editor")

        workspace.requestReconciliation()
        #expect(monitor.menuApps.first?.icon === live.icon)
        let restored = makeMonitor(workspace: FakeWorkspaceMonitor())
        #expect(restored.menuApps.first?.name == "Editor")
    }

    @Test
    func `Icon-only live metadata changes update stopped entries`() throws {
        let saved = StoredApp(id: "editor", name: "Editor", iconData: Data())
        preferences.defaults.set(try JSONEncoder().encode(["editor": saved]), forKey: "enabledApps")
        let workspace = FakeWorkspaceMonitor()
        let monitor = makeMonitor(workspace: workspace)
        let old = try #require(monitor.menuApps.first)
        let live = makeApplication(id: "editor", name: "Editor", pid: 1)
        workspace.sendLaunch(live)
        workspace.sendTermination(live)
        let updated = try #require(monitor.menuApps.first)
        #expect(updated.name == old.name)
        #expect(updated.isRunning == old.isRunning)
        #expect(updated.icon !== old.icon)
        #expect(updated != old)
    }

    @Test
    func `Unchanged snapshot recovers a stopped helper and hiding does not disable it`() {
        let workspace = FakeWorkspaceMonitor(runningApplications: [
            makeApplication(id: "editor", name: "Editor", pid: 1)
        ])
        let caffeinate = FakeCaffeinateManager()
        let monitor = makeMonitor(workspace: workspace, caffeinate: caffeinate)
        monitor.setEnabled("editor", true)
        monitor.setExcluded("editor", true)
        #expect(monitor.menuApps.isEmpty)
        #expect(caffeinate.isRunning)
        caffeinate.stop()
        workspace.requestReconciliation()
        #expect(caffeinate.isRunning)
        #expect(monitor.isCaffeinateRunning)
    }

    @Test
    func `Unchanged snapshots do not republish app lists`() {
        let workspace = FakeWorkspaceMonitor(runningApplications: [
            makeApplication(id: "editor", name: "Editor", pid: 1)
        ])
        let monitor = makeMonitor(workspace: workspace)
        withObservationTracking {
            _ = monitor.menuApps
            _ = monitor.availableApps
            _ = monitor.hiddenApps
        } onChange: {
            Issue.record("An unchanged snapshot republished the app lists")
        }
        workspace.requestReconciliation()
        workspace.requestReconciliation()
    }

    @Test
    func `Display mode restarts an active helper but never starts an idle one`() {
        let workspace = FakeWorkspaceMonitor(runningApplications: [
            makeApplication(id: "editor", name: "Editor", pid: 1)
        ])
        let caffeinate = FakeCaffeinateManager()
        let monitor = makeMonitor(workspace: workspace, caffeinate: caffeinate)
        monitor.keepDisplayOn = true
        #expect(caffeinate.restartRequests.isEmpty)
        monitor.setEnabled("editor", true)
        #expect(caffeinate.requests.last?.keepDisplayOn == true)
        monitor.keepDisplayOn = false
        #expect(caffeinate.restartRequests == [false])
        #expect(caffeinate.isRunning)
        monitor.setEnabled("editor", false)
        monitor.keepDisplayOn = true
        #expect(caffeinate.restartRequests == [false])
        #expect(!caffeinate.isRunning)
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
        AppMonitor(
            workspaceMonitor: workspace,
            caffeinateManager: caffeinate,
            defaults: preferences.defaults,
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

    func sendLaunch(_ application: WorkspaceApplication) {
        storedRunningApplications.append(application)
        handlers?.didLaunch(application)
    }

    func sendTermination(_ application: WorkspaceApplication) {
        storedRunningApplications.removeAll {
            $0.processIdentifier == application.processIdentifier
        }
        handlers?.didTerminate()
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

private final class TestPreferences {
    let suiteName = "AppMonitorTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
    }
}
