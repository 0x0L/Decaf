import Foundation
import Testing
@testable import Decaf

@MainActor
struct CaffeinateManagerTests {
    @Test(arguments: [false, true])
    func `Real helper uses requested assertions and exits on stop`(keepDisplayOn: Bool) async throws {
        var launchedProcess: Process?
        let manager = CaffeinateManager { process in
            launchedProcess = process
            try process.run()
        }
        defer { manager.stop() }
        manager.update(shouldRun: true, keepDisplayOn: keepDisplayOn)
        let process = try #require(launchedProcess)
        #expect(manager.isRunning)
        #expect(process.executableURL?.path == "/usr/bin/caffeinate")
        #expect(process.arguments == [keepDisplayOn ? "-diw" : "-iw", String(ProcessInfo.processInfo.processIdentifier)])
        manager.stop()
        try await expectExited(process)
        #expect(!manager.isRunning)
    }

    @Test
    func `Repeated requests reuse the helper and destruction terminates it`() async throws {
        var launchedProcess: Process?
        var launchCount = 0
        var manager: CaffeinateManager? = CaffeinateManager { process in
            launchedProcess = process
            launchCount += 1
            try process.run()
        }
        defer { manager?.stop() }
        manager?.update(shouldRun: true, keepDisplayOn: false)
        manager?.update(shouldRun: true, keepDisplayOn: false)
        #expect(launchCount == 1)
        let process = try #require(launchedProcess)
        #expect(process.isRunning)
        manager = nil
        try await expectExited(process)
    }

    @Test
    func `Launch failures remain inactive and recover on a later check`() {
        var shouldFail = true
        var launchCount = 0
        let manager = CaffeinateManager { process in
            launchCount += 1
            if shouldFail { throw Failure.unavailable }
            try process.run()
        }
        defer { manager.stop() }
        manager.update(shouldRun: true, keepDisplayOn: false)
        manager.update(shouldRun: true, keepDisplayOn: false)
        #expect(!manager.isRunning)
        #expect(launchCount == 2)
        shouldFail = false
        manager.update(shouldRun: true, keepDisplayOn: false)
        #expect(manager.isRunning)
        #expect(launchCount == 3)
    }

    private func expectExited(_ process: Process) async throws {
        for _ in 0..<100 where process.isRunning {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!process.isRunning)
    }

    private enum Failure: Error { case unavailable }
}
