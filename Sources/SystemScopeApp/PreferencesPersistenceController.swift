import Foundation
import Observation

@MainActor
final class PreferencesPersistenceController {
    private let model: AppModel
    private var observationGeneration = 0
    private var persistenceTask: Task<Void, Never>?
    private var isStarted = false

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        observePreferences()
    }

    func stop(flushPendingChanges: Bool) {
        guard isStarted else { return }
        isStarted = false
        observationGeneration += 1
        persistenceTask?.cancel()
        persistenceTask = nil
        if flushPendingChanges {
            model.persistPreferences()
        }
    }

    private func observePreferences() {
        guard isStarted else { return }
        let generation = observationGeneration
        withObservationTracking {
            _ = model.monitorConfiguration
            _ = model.refreshInterval
            _ = model.temperatureUnit
            _ = model.showMenuBarSummary
            _ = model.pauseWhenOnBattery
            _ = model.includeProcessNamesInReport
            _ = model.includeVolumeNamesInReport
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self,
                      self.isStarted,
                      self.observationGeneration == generation else { return }
                self.schedulePersistence()
                self.observePreferences()
            }
        }
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        let generation = observationGeneration
        persistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled,
                  let self,
                  self.isStarted,
                  self.observationGeneration == generation else { return }
            self.model.persistPreferences()
            self.persistenceTask = nil
        }
    }
}
