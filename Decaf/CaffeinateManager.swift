import Foundation
import OSLog

@MainActor
protocol CaffeinateManaging: AnyObject {
    var isRunning: Bool { get }

    func update(shouldRun: Bool, keepDisplayOn: Bool)
    func restart(keepDisplayOn: Bool)
    func stop()
}

@MainActor
final class CaffeinateManager: CaffeinateManaging {
    private var process: Process?
    private var lastLaunchFailure: String?
    private let launchProcess: (Process) throws -> Void
    private let logger = Logger(subsystem: "org.0x0L.Decaf", category: "Caffeinate")

    init(launchProcess: @escaping (Process) throws -> Void = { try $0.run() }) {
        self.launchProcess = launchProcess
    }

    var isRunning: Bool {
        process?.isRunning == true
    }

    func update(shouldRun: Bool, keepDisplayOn: Bool) {
        if shouldRun, !isRunning {
            start(keepDisplayOn: keepDisplayOn)
        } else if !shouldRun {
            stop()
        }
    }

    func restart(keepDisplayOn: Bool) {
        stop()
        start(keepDisplayOn: keepDisplayOn)
    }

    func stop() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        lastLaunchFailure = nil
    }

    private func start(keepDisplayOn: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        process.arguments = keepDisplayOn ? ["-diw", pid] : ["-iw", pid]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try launchProcess(process)
            self.process = process
            if lastLaunchFailure != nil {
                logger.notice("Caffeinate recovered after a launch failure")
                lastLaunchFailure = nil
            }
        } catch {
            self.process = nil
            let failure = error.localizedDescription
            if failure != lastLaunchFailure {
                logger.error("Failed to start caffeinate: \(failure, privacy: .public)")
                lastLaunchFailure = failure
            }
        }
    }

    deinit {
        if let process, process.isRunning {
            process.terminate()
        }
    }
}
