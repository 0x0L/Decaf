import AppKit

struct AppMetadata {
    let name: String
    let icon: NSImage
}

struct AppPresentationInput {
    let runningBundleIDs: Set<String>
    let enabledApps: [String: StoredApp]
    let excludedApps: Set<String>
    let excludedAppInfo: [String: StoredApp]
}

struct AppPresentationState {
    var menuApps: [AppEntry] = []
    var availableApps: [AppEntry] = []
    var hiddenApps: [AppEntry] = []
}

enum AppPresentationBuilder {
    static func build(
        input: AppPresentationInput,
        metadataCache: [String: AppMetadata]
    ) -> AppPresentationState {
        var state = AppPresentationState()
        let bundleIDs = input.runningBundleIDs
            .union(input.enabledApps.keys)
            .union(input.excludedAppInfo.keys)

        // AppMonitor supplies metadata for both live and persisted entries.
        for bundleID in bundleIDs {
            guard let metadata = metadataCache[bundleID] else { continue }
            let isRunning = input.runningBundleIDs.contains(bundleID)
            let entry = AppEntry(
                id: bundleID, name: metadata.name, icon: metadata.icon, isRunning: isRunning
            )
            if input.excludedApps.contains(bundleID) {
                if isRunning || input.excludedAppInfo[bundleID] != nil {
                    state.hiddenApps.append(entry)
                }
            } else if isRunning {
                state.availableApps.append(entry)
                state.menuApps.append(entry)
            } else if input.enabledApps[bundleID] != nil {
                state.menuApps.append(entry)
            }
        }

        state.menuApps.sort(by: AppEntry.runningFirst)
        state.availableApps.sort(by: AppEntry.alphabetical)
        state.hiddenApps.sort(by: AppEntry.alphabetical)
        return state
    }
}
