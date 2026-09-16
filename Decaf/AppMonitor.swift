import AppKit
import Observation
import OSLog

@MainActor
@Observable
final class AppMonitor {
    private(set) var menuApps: [AppEntry] = []
    private(set) var enabledApps: [String: StoredApp] = [:]
    private(set) var availableApps: [AppEntry] = []
    private(set) var hiddenApps: [AppEntry] = []
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
    @ObservationIgnored private var runningBundleIDs: Set<String> = []
    @ObservationIgnored private var liveMetadataBundleIDs: Set<String> = []
    @ObservationIgnored private var metadataCache: [String: AppMetadata] = [:]
    @ObservationIgnored private var excludedAppInfo: [String: StoredApp] = [:]
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
            reconciliationInterval: 0.5
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
           let decoded = try? JSONDecoder().decode([String: StoredApp].self, from: data) {
            enabledApps = decoded
        }
        if let data = defaults.data(forKey: Self.excludedAppInfoKey),
           let decoded = try? JSONDecoder().decode([String: StoredApp].self, from: data) {
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
            didTerminate: { [weak self] in
                self?.applicationDidTerminate()
            },
            needsReconciliation: { [weak self] in
                self?.reconcile()
            }
        ))
        reconcile()

        if reconciliationInterval > 0 {
            // Books can quit its UI without an exit event. Per-app KVO was removed
            // after crashes; keep polling for activation-policy changes.
            let timer = Timer(
                timeInterval: reconciliationInterval,
                repeats: true
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.reconcile()
                }
            }
            timer.tolerance = min(30, reconciliationInterval * 0.1)
            RunLoop.main.add(timer, forMode: .common)
            reconciliationTimer = timer
        }
    }

    deinit {
        reconciliationTimer?.invalidate()
    }

    func setEnabled(_ bundleID: String, _ enabled: Bool) {
        if enabled {
            guard let metadata = metadataCache[bundleID] else { return }
            enabledApps[bundleID] = StoredApp(id: bundleID, name: metadata.name, iconData: metadata.icon.pngData)
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
                excludedAppInfo[bundleID] = StoredApp(
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

        runningBundleIDs.insert(bundleID)
        cacheMetadata(for: application, bundleID: bundleID)
        signposter.emitEvent("Application Launched")
        publishState()
    }

    private func applicationDidTerminate() {
        signposter.emitEvent("Application Terminated")
        // Refresh the snapshot rather than relying on a terminated app’s metadata.
        reconcile()
    }

    private func reconcile() {
        let interval = signposter.beginInterval("Workspace Reconciliation")
        defer {
            signposter.endInterval("Workspace Reconciliation", interval)
        }

        var currentBundleIDs: Set<String> = []
        var metadataChanged = false

        for application in workspaceMonitor.runningApplications
        where application.activationPolicy == .regular {
            guard let bundleID = application.bundleIdentifier else { continue }
            currentBundleIDs.insert(bundleID)
            if cacheMetadata(for: application, bundleID: bundleID) { metadataChanged = true }
        }

        if currentBundleIDs == runningBundleIDs, !metadataChanged, lastRequestedCaffeinateState != nil {
            // An unchanged app list must still recover an unexpectedly exited helper.
            updateCaffeinate(forceCheck: true)
            return
        }
        runningBundleIDs = currentBundleIDs
        publishState(forceCaffeinateCheck: true)
    }

    @discardableResult
    private func cacheMetadata(for application: WorkspaceApplication, bundleID: String) -> Bool {
        // Saved metadata is a fallback until the app first appears in this session.
        guard liveMetadataBundleIDs.insert(bundleID).inserted else { return false }
        let saved = metadataCache[bundleID]
        let metadata = AppMetadata(
            name: application.localizedName ?? saved?.name ?? bundleID,
            icon: application.icon ?? saved?.icon ?? NSImage()
        )
        metadataCache[bundleID] = metadata

        if enabledApps[bundleID] != nil || excludedAppInfo[bundleID] != nil {
            let stored = StoredApp(id: bundleID, name: metadata.name, iconData: metadata.icon.pngData)
            if let previous = enabledApps[bundleID], previous != stored {
                enabledApps[bundleID] = stored
                persistEnabledApps()
            }
            if let previous = excludedAppInfo[bundleID], previous != stored {
                excludedAppInfo[bundleID] = stored
                persistExcludedInfo()
            }
        }
        return true
    }

    private func publishState(forceCaffeinateCheck: Bool = false) {
        let presentation = AppPresentationBuilder.build(
            input: AppPresentationInput(
                runningBundleIDs: runningBundleIDs,
                enabledApps: enabledApps,
                excludedApps: excludedApps,
                excludedAppInfo: excludedAppInfo
            ),
            metadataCache: metadataCache
        )

        publish(presentation)
        updateCaffeinate(forceCheck: forceCaffeinateCheck)
    }

    private func publish(_ presentation: AppPresentationState) {
        var didPublish = false

        if presentation.menuApps != menuApps {
            menuApps = presentation.menuApps
            didPublish = true
        }
        if presentation.availableApps != availableApps {
            availableApps = presentation.availableApps
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

    private func updateCaffeinate(forceCheck: Bool) {
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
