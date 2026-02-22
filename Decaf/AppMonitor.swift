import AppKit
import Observation

extension NSImage {
    var pngData: Data {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return Data() }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}

struct RunningApp: Identifiable, Equatable {
    let id: String // bundleIdentifier
    let name: String
    let icon: NSImage
    var isRunning: Bool

    static func == (lhs: RunningApp, rhs: RunningApp) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.isRunning == rhs.isRunning
    }
}

struct EnabledApp: Codable {
    let id: String
    let name: String
    let iconData: Data

    var icon: NSImage {
        NSImage(data: iconData) ?? NSImage()
    }
}

@Observable
final class AppMonitor {
    private(set) var apps: [RunningApp] = []
    private(set) var enabledApps: [String: EnabledApp] = [:]

    var isCaffeinateRunning: Bool {
        caffeinateProcess?.isRunning == true
    }

    var keepDisplayOn: Bool {
        didSet {
            defaults.set(keepDisplayOn, forKey: Self.keepDisplayOnKey)
            if isCaffeinateRunning {
                stopCaffeinate()
                updateCaffeinate()
            }
        }
    }

    // MARK: - Private

    private(set) var excludedApps: Set<String> = ["com.apple.finder"] {
        didSet {
            defaults.set(Array(excludedApps), forKey: Self.excludedAppsKey)
        }
    }

    private var caffeinateProcess: Process?
    private var pollTimer: Timer?
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
        refreshRunningApps()
        refreshSettingsApps()
        updateCaffeinate()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshRunningApps()
            self?.refreshSettingsApps()
            self?.updateCaffeinate()
        }
    }

    deinit {
        pollTimer?.invalidate()
        stopCaffeinate()
    }

    // MARK: - Public

    func setEnabled(_ bundleID: String, _ enabled: Bool) {
        if enabled {
            if let app = apps.first(where: { $0.id == bundleID }) {
                let iconData = app.icon.pngData
                enabledApps[bundleID] = EnabledApp(id: bundleID, name: app.name, iconData: iconData)
            }
        } else {
            enabledApps.removeValue(forKey: bundleID)
        }
        persist()
        refreshRunningApps()
        updateCaffeinate()
    }

    func isEnabled(_ bundleID: String) -> Bool {
        enabledApps[bundleID] != nil
    }

    private(set) var visibleApps: [RunningApp] = []
    private(set) var hiddenApps: [RunningApp] = []

    func setExcluded(_ bundleID: String, _ excluded: Bool) {
        if excluded, let idx = visibleApps.firstIndex(where: { $0.id == bundleID }) {
            let app = visibleApps.remove(at: idx)
            hiddenApps.append(app)
            hiddenApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            apps.removeAll { $0.id == bundleID }
            excludedApps.insert(bundleID)
            updateCaffeinate()
            // Persist icon data in the background — PNG encoding is expensive
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let iconData = app.icon.pngData
                let info = EnabledApp(id: bundleID, name: app.name, iconData: iconData)
                DispatchQueue.main.async {
                    self?.excludedAppInfo[bundleID] = info
                    self?.persistExcludedInfo()
                }
            }
        } else if !excluded, let idx = hiddenApps.firstIndex(where: { $0.id == bundleID }) {
            let app = hiddenApps.remove(at: idx)
            visibleApps.append(app)
            visibleApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            if app.isRunning {
                apps.append(app)
                apps.sort {
                    if $0.isRunning != $1.isRunning { return $0.isRunning }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
            excludedApps.remove(bundleID)
            excludedAppInfo.removeValue(forKey: bundleID)
            persistExcludedInfo()
            updateCaffeinate()
        }
    }

    // MARK: - App List

    private func refreshRunningApps() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !excludedApps.contains($0.bundleIdentifier ?? "") }

        // Build merged list: running apps + toggled-but-quit apps
        var seen = Set<String>()
        var merged: [RunningApp] = []

        // Running apps first
        for app in running {
            guard let id = app.bundleIdentifier, !seen.contains(id) else { continue }
            seen.insert(id)
            merged.append(RunningApp(
                id: id,
                name: app.localizedName ?? id,
                icon: app.icon ?? NSImage(),
                isRunning: true
            ))
        }

        // Toggled-but-quit apps
        for (id, stored) in enabledApps where !seen.contains(id) {
            merged.append(RunningApp(
                id: id,
                name: stored.name,
                icon: stored.icon,
                isRunning: false
            ))
        }

        // Sort: running first, then alphabetically
        merged.sort {
            if $0.isRunning != $1.isRunning { return $0.isRunning }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        if merged != apps {
            apps = merged
        }
    }

    private func refreshSettingsApps() {
        let allRunning = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        var visible: [RunningApp] = []
        var hidden: [RunningApp] = []
        var seenHidden = Set<String>()

        for app in allRunning {
            guard let id = app.bundleIdentifier else { continue }
            let entry = RunningApp(
                id: id,
                name: app.localizedName ?? id,
                icon: app.icon ?? NSImage(),
                isRunning: true
            )
            if excludedApps.contains(id) {
                hidden.append(entry)
                seenHidden.insert(id)
            } else {
                visible.append(entry)
            }
        }

        // Show excluded apps that aren't currently running (from persisted info)
        for (id, info) in excludedAppInfo where !seenHidden.contains(id) && excludedApps.contains(id) {
            hidden.append(RunningApp(id: id, name: info.name, icon: info.icon, isRunning: false))
        }

        visible.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        hidden.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if visible != visibleApps { visibleApps = visible }
        if hidden != hiddenApps { hiddenApps = hidden }
    }

    private func persistExcludedInfo() {
        if let data = try? JSONEncoder().encode(excludedAppInfo) {
            defaults.set(data, forKey: Self.excludedAppInfoKey)
        }
    }

    // MARK: - Caffeinate

    private func updateCaffeinate() {
        let shouldRun = apps.contains { $0.isRunning && enabledApps[$0.id] != nil }

        if shouldRun, !isCaffeinateRunning {
            startCaffeinate()
        } else if !shouldRun, isCaffeinateRunning {
            stopCaffeinate()
        }
    }

    private func startCaffeinate() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = keepDisplayOn ? ["-di"] : ["-i"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateCaffeinate()
            }
        }

        do {
            try process.run()
            caffeinateProcess = process
            #if DEBUG
                print("caffeinate started")
            #endif
        } catch {
            caffeinateProcess = nil
            #if DEBUG
                print("Failed to start caffeinate: \(error)")
            #endif
        }
    }

    private func stopCaffeinate() {
        guard let process = caffeinateProcess, process.isRunning else { return }
        process.terminate()
        caffeinateProcess = nil
        #if DEBUG
            print("caffeinate stopped")
        #endif
    }

    // MARK: - Persistence

    private func persist() {
        if let data = try? JSONEncoder().encode(enabledApps) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
