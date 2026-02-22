import Foundation

final class CaffeinateManager {
    private var process: Process?

    var isRunning: Bool { process?.isRunning == true }

    func update(shouldRun: Bool, keepDisplayOn: Bool) {
        if shouldRun, !isRunning {
            start(keepDisplayOn: keepDisplayOn)
        } else if !shouldRun, isRunning {
            stop()
        }
    }

    func restart(keepDisplayOn: Bool) {
        stop()
        start(keepDisplayOn: keepDisplayOn)
    }

    func stop() {
        guard let process, process.isRunning else { return }
        process.terminate()
        self.process = nil
        #if DEBUG
            print("caffeinate stopped")
        #endif
    }

    private func start(keepDisplayOn: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        process.arguments = keepDisplayOn ? ["-diw", pid] : ["-iw", pid]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            self.process = process
            #if DEBUG
                print("caffeinate started")
            #endif
        } catch {
            self.process = nil
            #if DEBUG
                print("Failed to start caffeinate: \(error)")
            #endif
        }
    }

    deinit {
        stop()
    }
}
