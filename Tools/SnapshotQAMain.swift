import AppKit
import Foundation
import TraceHaloCore

@main
struct SnapshotQAMain {
    @MainActor
    static func main() async {
        guard let path = CommandLine.arguments.dropFirst().first, path.hasPrefix("/") else {
            print("Usage: TraceHaloSnapshotQA /absolute/output/directory")
            return
        }

        _ = NSApplication.shared
        UserDefaults.standard.setVolatileDomain(
            [
                "launchDestination": AppDestination.dashboard.rawValue,
                "appearanceMode": "system",
                AppLanguagePreference.storageKey: AppLanguagePreference.simplifiedChinese.rawValue,
            ],
            forName: UserDefaults.argumentDomain
        )
        let repositoryRoot = FileManager.default.currentDirectoryPath
        let appIconPaths = [
            repositoryRoot + "/.build/TraceHalo.app/Contents/Resources/AppIcon.icns",
            repositoryRoot
                + "/Xcode/TraceHalo/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png",
            repositoryRoot + "/Resources/TraceHalo-AppIcon-Source.png",
        ]
        if let appIcon = appIconPaths.lazy.compactMap(NSImage.init(contentsOfFile:)).first {
            NSApplication.shared.applicationIconImage = appIcon
        }
        let model = AppModel()
        model.monitorConfiguration = .standard
        model.refreshInterval = 2
        model.pauseWhenOnBattery = true
        model.showMenuBarSummary = true
        model.includeProcessNamesInReport = false
        model.includeVolumeNamesInReport = false
        await model.refreshAll()
        await model.preloadToolData()
        await model.loadSelectedApplicationDetails()

        var portableSnapshot = SystemSnapshot.fixture
        portableSnapshot.identity.modelName = "MacBook Pro"
        portableSnapshot.identity.modelIdentifier = "Mac15,6"
        portableSnapshot.battery = BatteryState(
            availability: .available,
            chargePercent: 78,
            isCharging: false,
            isOnExternalPower: false,
            health: .good,
            healthBasis: .systemReported
        )
        let portableSettingsModel = AppModel(
            metricsProvider: SnapshotQAMetricsProvider(value: portableSnapshot)
        )
        portableSettingsModel.refreshInterval = 2
        portableSettingsModel.pauseWhenOnBattery = true
        portableSettingsModel.showMenuBarSummary = true
        portableSettingsModel.includeProcessNamesInReport = false
        portableSettingsModel.includeVolumeNamesInReport = false
        await portableSettingsModel.refreshAll()
        do {
            try UISnapshotCapture.captureAll(
                model: model,
                portableSettingsModel: portableSettingsModel,
                outputDirectory: URL(fileURLWithPath: path, isDirectory: true)
            )
            print("Captured UI snapshots in \(path)")
        } catch {
            print("UI snapshot capture failed: \(error.localizedDescription)")
        }
    }
}

private struct SnapshotQAMetricsProvider: SystemMetricsProviding {
    let value: SystemSnapshot

    func snapshot() async -> SystemSnapshot {
        value
    }
}
