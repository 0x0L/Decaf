import AppKit

struct AppMetadata {
    let name: String
    let icon: NSImage
}

struct AppPresentationInput {
    let runningBundleIDs: Set<String>
    let enabledApps: [String: EnabledApp]
    let excludedApps: Set<String>
    let excludedAppInfo: [String: EnabledApp]
}

struct AppPresentationState {
    var apps: [RunningApp] = []
    var visibleApps: [RunningApp] = []
    var hiddenApps: [RunningApp] = []
}

enum AppPresentationBuilder {
    static func build(
        input: AppPresentationInput,
        metadataCache: inout [String: AppMetadata]
    ) -> AppPresentationState {
        var state = AppPresentationState()
        appendRunningApps(
            input: input,
            metadataCache: metadataCache,
            state: &state
        )
        appendPersistedApps(
            input: input,
            metadataCache: &metadataCache,
            state: &state
        )

        state.apps.sort(by: RunningApp.runningFirst)
        state.visibleApps.sort(by: RunningApp.alphabetical)
        state.hiddenApps.sort(by: RunningApp.alphabetical)
        return state
    }

    private static func appendRunningApps(
        input: AppPresentationInput,
        metadataCache: [String: AppMetadata],
        state: inout AppPresentationState
    ) {
        for bundleID in input.runningBundleIDs {
            guard let metadata = metadataCache[bundleID] else { continue }
            let app = RunningApp(
                id: bundleID,
                name: metadata.name,
                icon: metadata.icon,
                isRunning: true
            )

            if input.excludedApps.contains(bundleID) {
                state.hiddenApps.append(app)
            } else {
                state.visibleApps.append(app)
                state.apps.append(app)
            }
        }
    }

    private static func appendPersistedApps(
        input: AppPresentationInput,
        metadataCache: inout [String: AppMetadata],
        state: inout AppPresentationState
    ) {
        for (bundleID, stored) in input.enabledApps
        where !input.runningBundleIDs.contains(bundleID)
            && !input.excludedApps.contains(bundleID) {
            let metadata = cachedMetadata(
                bundleID: bundleID,
                stored: stored,
                metadataCache: &metadataCache
            )
            state.apps.append(RunningApp(
                id: bundleID,
                name: metadata.name,
                icon: metadata.icon,
                isRunning: false
            ))
        }

        for (bundleID, stored) in input.excludedAppInfo
        where !input.runningBundleIDs.contains(bundleID)
            && input.excludedApps.contains(bundleID) {
            let metadata = cachedMetadata(
                bundleID: bundleID,
                stored: stored,
                metadataCache: &metadataCache
            )
            state.hiddenApps.append(RunningApp(
                id: bundleID,
                name: metadata.name,
                icon: metadata.icon,
                isRunning: false
            ))
        }
    }

    private static func cachedMetadata(
        bundleID: String,
        stored: EnabledApp,
        metadataCache: inout [String: AppMetadata]
    ) -> AppMetadata {
        if let metadata = metadataCache[bundleID] {
            return metadata
        }

        let metadata = AppMetadata(name: stored.name, icon: stored.icon)
        metadataCache[bundleID] = metadata
        return metadata
    }
}
