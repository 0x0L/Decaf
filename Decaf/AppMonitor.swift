import AppKit
import Observation

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

    // MARK: - Private

    private var caffeinateProcess: Process?
    private var pollTimer: Timer?
    private let defaults = UserDefaults.standard
    private static let defaultsKey = "enabledApps"

    // MARK: - Init

    init() {
        if let data = defaults.data(forKey: Self.defaultsKey),
           let decoded = try? JSONDecoder().decode([String: EnabledApp].self, from: data) {
            enabledApps = decoded
        }
        refreshRunningApps()
        updateCaffeinate()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshRunningApps()
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
                let iconData = app.icon.tiffRepresentation ?? Data()
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

    // MARK: - App List

    private func refreshRunningApps() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != "com.apple.finder" }

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
        process.arguments = ["-i"]
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
