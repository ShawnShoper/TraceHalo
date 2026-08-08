import Observation

@MainActor
@Observable
final class AppNavigationRouter {
    var destination: AppDestination?

    init(destination: AppDestination? = nil) {
        self.destination = destination
    }

    func navigate(to destination: AppDestination) {
        guard self.destination != destination else { return }
        self.destination = destination
    }
}
