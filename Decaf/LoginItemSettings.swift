import Observation
import ServiceManagement

@MainActor
protocol LoginItemServicing {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {}

@MainActor
@Observable
final class LoginItemSettings {
    private(set) var status: SMAppService.Status
    var errorMessage: String?
    @ObservationIgnored private let service: any LoginItemServicing

    var isEnabled: Bool { status == .enabled }
    var requiresApproval: Bool { status == .requiresApproval }

    init(service: any LoginItemServicing = SMAppService.mainApp) {
        self.service = service
        status = service.status
    }

    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        // Refreshing status must never trigger another registration operation.
        refresh()
    }
}
