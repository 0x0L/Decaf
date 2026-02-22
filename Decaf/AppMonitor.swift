import AppKit
import Observation

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
            if isCaffeinateRunning {
                caffeinateManager.restart(keepDisplayOn: keepDisplayOn)
                isCaffeinateRunning = caffeinateManager.isRunning
            }
        }
    }

    // MARK: - Private

    private(set) var excludedApps: Set<String> = ["com.apple.finder"] {
        didSet {
            guard !isInitializing else { return }
            defaults.set(Array(excludedApps), forKey: Self.excludedAppsKey)
        }
    }

    private let caffeinateManager = CaffeinateManager()
    private var pollTimer: Timer?
    private var isInitializing = true
    private let defaults = UserDefaults.standard
    private static let defaultsKey = "enabledApps"
    private static let keepDisplayOnKey = "keepDisplayOn"
    private static let excludedAppsKey = "excludedApps"
    private static let excludedAppInfoKey = "excludedAppInfo"
    private static let defaultExcludedApps: Set<String> = ["com.apple.finder"]
    private var excludedAppInfo: [String: EnabledApp] = [:]

    // MARK: - Init

    init() {
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
        isInitializing = false
        refreshAll()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshAll()
        }
    }

    deinit {
        pollTimer?.invalidate()
        caffeinateManager.stop()
    }

    // MARK: - Public

    func setEnabled(_ bundleID: String, _ enabled: Bool) {
        if enabled {
            if let app = apps.first(where: { $0.id == bundleID }) {
                enabledApps[bundleID] = EnabledApp(id: bundleID, name: app.name, iconData: app.icon.pngData)
            }
        } else {
            enabledApps.removeValue(forKey: bundleID)
        }
        refreshAll()
        persist()
    }

    func isEnabled(_ bundleID: String) -> Bool {
        enabledApps[bundleID] != nil
    }

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        // Capture before refreshAll changes the lists
        let appForInfo = excluded ? visibleApps.first(where: { $0.id == bundleID }) : nil

        if excluded {
            excludedApps.insert(bundleID)
        } else {
            excludedApps.remove(bundleID)
            excludedAppInfo.removeValue(forKey: bundleID)
        }

        // Update UI immediately
        refreshAll()

        // Persist after UI update (PNG encoding + JSON serialization is slow)
        if let app = appForInfo {
            excludedAppInfo[bundleID] = EnabledApp(id: bundleID, name: app.name, iconData: app.icon.pngData)
        }
        persistExcludedInfo()
    }

    // MARK: - Refresh

    private func refreshAll() {
        let snapshot = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        var seen = Set<String>()
        var newApps: [RunningApp] = []
        var visible: [RunningApp] = []
        var hidden: [RunningApp] = []

        for nsApp in snapshot {
            guard let id = nsApp.bundleIdentifier, !seen.contains(id) else { continue }
            seen.insert(id)

            let entry = RunningApp(
                id: id,
                name: nsApp.localizedName ?? id,
                icon: nsApp.icon ?? NSImage(),
                isRunning: true
            )

            if excludedApps.contains(id) {
                hidden.append(entry)
            } else {
                visible.append(entry)
                newApps.append(entry)
            }
        }

        // Toggled-but-quit apps (menu bar list only)
        for (id, stored) in enabledApps where !seen.contains(id) && !excludedApps.contains(id) {
            newApps.append(RunningApp(id: id, name: stored.name, icon: stored.icon, isRunning: false))
        }

        // Excluded apps that aren't currently running (settings list only)
        for (id, info) in excludedAppInfo where !seen.contains(id) && excludedApps.contains(id) {
            hidden.append(RunningApp(id: id, name: info.name, icon: info.icon, isRunning: false))
        }

        newApps.sort(by: RunningApp.runningFirst)
        visible.sort(by: RunningApp.alphabetical)
        hidden.sort(by: RunningApp.alphabetical)

        if newApps != apps { apps = newApps }
        if visible != visibleApps { visibleApps = visible }
        if hidden != hiddenApps { hiddenApps = hidden }

        // Update caffeinate
        let shouldRun = newApps.contains { $0.isRunning && enabledApps[$0.id] != nil }
        caffeinateManager.update(shouldRun: shouldRun, keepDisplayOn: keepDisplayOn)
        isCaffeinateRunning = caffeinateManager.isRunning
    }

    // MARK: - Persistence

    private func persist() {
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
