import AppKit

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

    nonisolated static func alphabetical(_ lhs: RunningApp, _ rhs: RunningApp) -> Bool {
        lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    nonisolated static func runningFirst(_ lhs: RunningApp, _ rhs: RunningApp) -> Bool {
        if lhs.isRunning != rhs.isRunning { return lhs.isRunning }
        return alphabetical(lhs, rhs)
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
