import Observation

enum MonitorWorkspace: Equatable {
    case live(MenuBarDashboardSection)
    case menuBarLayout
}

struct DashboardSectionRequest: Equatable {
    let section: MenuBarDashboardSection
    let sequence: UInt
}

@MainActor
@Observable
final class AppNavigationRouter {
    private(set) var destination: AppDestination?
    private(set) var dashboardSectionRequest: DashboardSectionRequest?
    private var dashboardSectionSequence: UInt = 0

    init(destination: AppDestination? = nil) {
        self.destination = destination == .monitor ? .dashboard : destination
    }

    func navigate(to destination: AppDestination) {
        let destination: AppDestination = destination == .monitor ? .dashboard : destination
        if dashboardSectionRequest != nil {
            dashboardSectionRequest = nil
        }
        guard self.destination != destination else { return }
        self.destination = destination
    }

    func openMonitor(_ workspace: MonitorWorkspace) {
        switch workspace {
        case .live(let section):
            dashboardSectionSequence &+= 1
            dashboardSectionRequest = DashboardSectionRequest(section: section, sequence: dashboardSectionSequence)
            if destination != .dashboard { destination = .dashboard }
        case .menuBarLayout:
            if dashboardSectionRequest != nil { dashboardSectionRequest = nil }
            if destination != .monitor { destination = .monitor }
        }
    }
}
