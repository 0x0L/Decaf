import ServiceManagement
import Testing
@testable import Decaf

@MainActor
struct LoginItemSettingsTests {
    @Test
    func `User actions mutate the service once and refresh actual status`() {
        let service = FakeLoginItemService()
        let settings = LoginItemSettings(service: service)
        settings.setEnabled(true)
        #expect(settings.isEnabled)
        #expect(service.operations == [true])
        settings.setEnabled(false)
        #expect(!settings.isEnabled)
        #expect(service.operations == [true, false])
    }

    @Test(arguments: [true, false])
    func `Failed operations do not cause an opposite operation`(enable: Bool) {
        let service = FakeLoginItemService()
        service.status = enable ? .notRegistered : .enabled
        service.shouldFail = true
        let settings = LoginItemSettings(service: service)
        settings.setEnabled(enable)
        #expect(settings.isEnabled == !enable)
        #expect(settings.errorMessage != nil)
        #expect(service.operations == [enable])
        settings.refresh()
        #expect(service.operations == [enable])
    }

    @Test
    func `Approval and external changes refresh without registration`() {
        let service = FakeLoginItemService()
        service.registrationStatus = .requiresApproval
        let settings = LoginItemSettings(service: service)
        settings.setEnabled(true)
        #expect(settings.requiresApproval)
        #expect(!settings.isEnabled)
        service.status = .enabled
        settings.refresh()
        #expect(settings.isEnabled)
        #expect(!settings.requiresApproval)
        service.status = .notRegistered
        settings.refresh()
        #expect(!settings.isEnabled)
        #expect(service.operations == [true])
    }
}

@MainActor
private final class FakeLoginItemService: LoginItemServicing {
    var status: SMAppService.Status = .notRegistered
    var registrationStatus: SMAppService.Status = .enabled
    var shouldFail = false
    var operations: [Bool] = []

    func register() throws {
        operations.append(true)
        if shouldFail { throw Failure.denied }
        status = registrationStatus
    }

    func unregister() throws {
        operations.append(false)
        if shouldFail { throw Failure.denied }
        status = .notRegistered
    }

    private enum Failure: Error { case denied }
}
