import AppKit

extension NSImage {
    var pngData: Data {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return Data() }
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}

struct AppEntry: Identifiable, Equatable {
    let id: String // bundleIdentifier
    let name: String
    let icon: NSImage
    var isRunning: Bool

    static func == (lhs: AppEntry, rhs: AppEntry) -> Bool {
        // Icons are cached objects: identity detects replacements without image encoding.
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.isRunning == rhs.isRunning && lhs.icon === rhs.icon
    }

    nonisolated static func alphabetical(_ lhs: AppEntry, _ rhs: AppEntry) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    nonisolated static func runningFirst(_ lhs: AppEntry, _ rhs: AppEntry) -> Bool {
        if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
        return alphabetical(lhs, rhs)
    }
}

struct StoredApp: Codable, Equatable {
    let id: String
    let name: String
    let iconData: Data

    var icon: NSImage {
        NSImage(data: iconData) ?? NSImage()
    }
}
