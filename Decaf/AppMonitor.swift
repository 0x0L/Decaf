import AppKit
import Observation

struct RunningApp: Identifiable {
    let id: String // bundleIdentifier
    let name: String
    let icon: NSImage
    var isRunning: Bool
}

@Observable
final class AppMonitor {
    private(set) var apps: [RunningApp] = []
    private(set) var enabledBundleIDs: Set<String> = []

    var isCaffeinateRunning: Bool {
        caffeinateProcess?.isRunning == true
    }

    // MARK: - Private

    private var caffeinateProcess: Process?
    private let defaults = UserDefaults.standard
    private static let defaultsKey = "enabledBundleIDs"

    // MARK: - Init

    init() {
        enabledBundleIDs = Set(
            defaults.stringArray(forKey: Self.defaultsKey) ?? []
        )
        refreshRunningApps()
        updateCaffeinate()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    deinit {
        let center = NSWorkspace.shared.notificationCenter
        center.removeObserver(self, name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.removeObserver(self, name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        stopCaffeinate()
    }

    // MARK: - Public

    func setEnabled(_ bundleID: String, _ enabled: Bool) {
        if enabled {
            enabledBundleIDs.insert(bundleID)
        } else {
            enabledBundleIDs.remove(bundleID)
        }
        persist()
        refreshRunningApps()
        updateCaffeinate()
    }

    func isEnabled(_ bundleID: String) -> Bool {
        enabledBundleIDs.contains(bundleID)
    }

    // MARK: - Workspace Notifications

    @objc private func appLaunched(_: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshRunningApps()
            self?.updateCaffeinate()
        }
    }

    @objc private func appTerminated(_: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.refreshRunningApps()
            self?.updateCaffeinate()
        }
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
        for id in enabledBundleIDs where !seen.contains(id) {
            let previous = apps.first { $0.id == id }
            merged.append(RunningApp(
                id: id,
                name: previous?.name ?? id,
                icon: previous?.icon ?? NSImage(),
                isRunning: false
            ))
        }

        // Sort: running first, then alphabetically
        merged.sort {
            if $0.isRunning != $1.isRunning { return $0.isRunning }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        apps = merged
    }

    // MARK: - Caffeinate

    private func updateCaffeinate() {
        let shouldRun = apps.contains { $0.isRunning && enabledBundleIDs.contains($0.id) }

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
        defaults.set(Array(enabledBundleIDs), forKey: Self.defaultsKey)
    }
}
