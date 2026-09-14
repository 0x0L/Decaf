import AppKit
import Observation
import OSLog

@MainActor
@Observable
final class AppMonitor {
    private(set) var apps: [RunningApp] = []
    private(set) var enabledApps: [String: EnabledApp] = [:]
    private(set) var visibleApps: [RunningApp] = []
    private(set) var hiddenApps: [RunningApp] = []
    private(set) var isCaffeinateRunning = false

    var keepDisplayOn: Bool {
        didSet {
            guard !isInitializing else { return }
            defaults.set(keepDisplayOn, forKey: Self.keepDisplayOnKey)

            if lastRequestedCaffeinateState == true {
                caffeinateManager.restart(keepDisplayOn: keepDisplayOn)
                isCaffeinateRunning = caffeinateManager.isRunning
            }
        }
    }

    private(set) var excludedApps: Set<String> = ["com.apple.finder"] {
        didSet {
            guard !isInitializing else { return }
            defaults.set(Array(excludedApps), forKey: Self.excludedAppsKey)
        }
    }

    @ObservationIgnored private let workspaceMonitor: any WorkspaceMonitoring
    @ObservationIgnored private let caffeinateManager: any CaffeinateManaging
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "Decaf",
        category: "AppMonitoring"
    )
    @ObservationIgnored private var reconciliationTimer: Timer?
    @ObservationIgnored private var runningProcessIDs: [String: Set<pid_t>] = [:]
    @ObservationIgnored private var metadataCache: [String: AppMetadata] = [:]
    @ObservationIgnored private var excludedAppInfo: [String: EnabledApp] = [:]
    @ObservationIgnored private var lastRequestedCaffeinateState: Bool?
    @ObservationIgnored private var isInitializing = true

    private static let defaultsKey = "enabledApps"
    private static let keepDisplayOnKey = "keepDisplayOn"
    private static let excludedAppsKey = "excludedApps"
    private static let excludedAppInfoKey = "excludedAppInfo"
    private static let defaultExcludedApps: Set<String> = ["com.apple.finder"]

    convenience init() {
        self.init(
            workspaceMonitor: SystemWorkspaceMonitor(),
            caffeinateManager: CaffeinateManager(),
            defaults: .standard,
            reconciliationInterval: 300
        )
    }

    init(
        workspaceMonitor: any WorkspaceMonitoring,
        caffeinateManager: any CaffeinateManaging,
        defaults: UserDefaults,
        reconciliationInterval: TimeInterval
    ) {
        self.workspaceMonitor = workspaceMonitor
        self.caffeinateManager = caffeinateManager
        self.defaults = defaults

        if let stored = defaults.stringArray(forKey: Self.excludedAppsKey) {
            excludedApps = Set(stored)
        } else {
            excludedApps = Self.defaultExcludedApps
        }
        keepDisplayOn = defaults.bool(forKey: Self.keepDisplayOnKey)

        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: EnabledApp].self, from: data) {
            enabledApps = decoded
        }
        if let data = defaults.data(forKey: Self.excludedAppInfoKey),
           let decoded = try? JSONDecoder().decode([String: EnabledApp].self, from: data) {
            excludedAppInfo = decoded
        }

        for (id, stored) in enabledApps {
            metadataCache[id] = AppMetadata(name: stored.name, icon: stored.icon)
        }
        for (id, stored) in excludedAppInfo where metadataCache[id] == nil {
            metadataCache[id] = AppMetadata(name: stored.name, icon: stored.icon)
        }

        isInitializing = false

        workspaceMonitor.startMonitoring(handlers: WorkspaceEventHandlers(
            didLaunch: { [weak self] application in
                self?.applicationDidLaunch(application)
            },
            didTerminate: { [weak self] application in
                self?.applicationDidTerminate(application)
            },
            needsReconciliation: { [weak self] in
                self?.reconcile()
            }
        ))
        reconcile()

        if reconciliationInterval > 0 {
            let timer = Timer.scheduledTimer(
                withTimeInterval: reconciliationInterval,
                repeats: true
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reconcile()
                }
            }
            timer.tolerance = min(30, reconciliationInterval * 0.1)
            reconciliationTimer = timer
        }
    }

    deinit {
        reconciliationTimer?.invalidate()
    }

    func setEnabled(_ bundleID: String, _ enabled: Bool) {
        if enabled {
            guard let metadata = metadataCache[bundleID] else { return }
            enabledApps[bundleID] = EnabledApp(
                id: bundleID,
                name: metadata.name,
                iconData: metadata.icon.pngData
            )
        } else {
            enabledApps.removeValue(forKey: bundleID)
        }

        publishState()
        persistEnabledApps()
    }

    func isEnabled(_ bundleID: String) -> Bool {
        enabledApps[bundleID] != nil
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        if excluded {
            excludedApps.insert(bundleID)
            if let metadata = metadataCache[bundleID] {
                excludedAppInfo[bundleID] = EnabledApp(
                    id: bundleID,
                    name: metadata.name,
                    iconData: metadata.icon.pngData
                )
            }
        } else {
            excludedApps.remove(bundleID)
            excludedAppInfo.removeValue(forKey: bundleID)
        }

        publishState()
        persistExcludedInfo()
    }

    private func applicationDidLaunch(_ application: WorkspaceApplication) {
        guard application.activationPolicy == .regular,
              let bundleID = application.bundleIdentifier else { return }

        runningProcessIDs[bundleID, default: []].insert(application.processIdentifier)
        cacheMetadata(for: application, bundleID: bundleID)
        signposter.emitEvent("Application Launched")
        publishState()
    }

    private func applicationDidTerminate(_ application: WorkspaceApplication) {
        if let bundleID = application.bundleIdentifier {
            runningProcessIDs[bundleID]?.remove(application.processIdentifier)
            if runningProcessIDs[bundleID]?.isEmpty == true {
                runningProcessIDs.removeValue(forKey: bundleID)
            }
        } else {
            for bundleID in Array(runningProcessIDs.keys) {
                runningProcessIDs[bundleID]?.remove(application.processIdentifier)
                if runningProcessIDs[bundleID]?.isEmpty == true {
                    runningProcessIDs.removeValue(forKey: bundleID)
                }
            }
        }

        signposter.emitEvent("Application Terminated")
        publishState()
    }

    private func reconcile() {
        let interval = signposter.beginInterval("Workspace Reconciliation")
        defer {
            signposter.endInterval("Workspace Reconciliation", interval)
        }

        var reconciledProcessIDs: [String: Set<pid_t>] = [:]

        for application in workspaceMonitor.runningApplications
        where application.activationPolicy == .regular {
            guard let bundleID = application.bundleIdentifier else { continue }
            reconciledProcessIDs[bundleID, default: []].insert(application.processIdentifier)
            cacheMetadata(for: application, bundleID: bundleID)
        }

        runningProcessIDs = reconciledProcessIDs
        publishState(forceCaffeinateCheck: true)
    }

    private func cacheMetadata(for application: WorkspaceApplication, bundleID: String) {
        guard metadataCache[bundleID] == nil else { return }
        metadataCache[bundleID] = AppMetadata(
            name: application.localizedName ?? bundleID,
            icon: application.icon ?? NSImage()
        )
    }

    private func publishState(forceCaffeinateCheck: Bool = false) {
        let runningBundleIDs = Set(runningProcessIDs.keys)
        let presentation = AppPresentationBuilder.build(
            input: AppPresentationInput(
                runningBundleIDs: runningBundleIDs,
                enabledApps: enabledApps,
                excludedApps: excludedApps,
                excludedAppInfo: excludedAppInfo
            ),
            metadataCache: &metadataCache
        )

        publish(presentation)
        updateCaffeinate(
            runningBundleIDs: runningBundleIDs,
            forceCheck: forceCaffeinateCheck
        )
    }

    private func publish(_ presentation: AppPresentationState) {
        var didPublish = false

        if presentation.apps != apps {
            apps = presentation.apps
            didPublish = true
        }
        if presentation.visibleApps != visibleApps {
            visibleApps = presentation.visibleApps
            didPublish = true
        }
        if presentation.hiddenApps != hiddenApps {
            hiddenApps = presentation.hiddenApps
            didPublish = true
        }

        if didPublish {
            signposter.emitEvent("Published App State")
        }
    }

    private func updateCaffeinate(
        runningBundleIDs: Set<String>,
        forceCheck: Bool
    ) {
        let shouldCaffeinate = runningBundleIDs.contains { enabledApps[$0] != nil }
        if forceCheck || shouldCaffeinate != lastRequestedCaffeinateState {
            caffeinateManager.update(
                shouldRun: shouldCaffeinate,
                keepDisplayOn: keepDisplayOn
            )
            lastRequestedCaffeinateState = shouldCaffeinate
        }

        let managerIsRunning = caffeinateManager.isRunning
        if managerIsRunning != isCaffeinateRunning {
            isCaffeinateRunning = managerIsRunning
            signposter.emitEvent("Caffeinate State Changed")
        }
    }

    private func persistEnabledApps() {
        if let data = try? JSONEncoder().encode(enabledApps) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }

    private func persistExcludedInfo() {
        if let data = try? JSONEncoder().encode(excludedAppInfo) {
            defaults.set(data, forKey: Self.excludedAppInfoKey)
        }
    }
}
