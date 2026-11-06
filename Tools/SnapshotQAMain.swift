import AppKit
import Darwin
import Foundation
import TraceHaloCore

@main
struct SnapshotQAMain {
    @MainActor
    static func main() async {
        guard let path = CommandLine.arguments.dropFirst().first, path.hasPrefix("/") else {
            fail("Usage: TraceHaloSnapshotQA /absolute/output/directory")
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

        let outputDirectory = URL(fileURLWithPath: path, isDirectory: true)
        let reportRegressionModel = await makeReportRegressionModel()
        do {
            if ProcessInfo.processInfo.environment["TRACEHALO_SNAPSHOT_REPORT_ONLY"] == "1" {
                try await UISnapshotCapture.captureReportRegression(
                    model: reportRegressionModel,
                    outputDirectory: outputDirectory
                )
            } else {
                try await captureAll(reportRegressionModel: reportRegressionModel, outputDirectory: outputDirectory)
            }
            print("Captured UI snapshots in \(path)")
        } catch {
            fail("UI snapshot capture failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func captureAll(reportRegressionModel: AppModel, outputDirectory: URL) async throws {
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
        portableSettingsModel.monitorConfiguration = .standard
        portableSettingsModel.refreshInterval = 2
        portableSettingsModel.pauseWhenOnBattery = true
        portableSettingsModel.showMenuBarSummary = true
        portableSettingsModel.includeProcessNamesInReport = false
        portableSettingsModel.includeVolumeNamesInReport = false
        await portableSettingsModel.refreshAll()
        try await UISnapshotCapture.captureAll(
            model: model,
            portableSettingsModel: portableSettingsModel,
            reportRegressionModel: reportRegressionModel,
            outputDirectory: outputDirectory
        )
    }

    @MainActor
    private static func makeReportRegressionModel() async -> AppModel {
        var snapshot = SystemSnapshot.fixture
        let longName = "TraceHaloQA" + String(repeating: "UnbrokenExecutableName", count: 5)
        // Reports omit volume mount paths. Include a synthetic executable path
        // in a process name to exercise wrapping without altering report privacy.
        let longPath = "/Users/TraceHalo-QA/Library/Application Support/Diagnostics/Workers/"
            + "ReportPreviewWrappingFixture.app/Contents/MacOS/ReportPreviewWrappingFixture"
        snapshot.cpu.topProcesses = [
            ProcessUsage(id: 101, name: longName, cpuPercent: 40, memoryBytes: 524_288),
            ProcessUsage(id: 102, name: longPath, cpuPercent: 20, memoryBytes: 262_144)
        ]
        if !snapshot.volumes.isEmpty {
            snapshot.volumes[0].name = "TraceHalo-QA-" + String(repeating: "LongVolumeLabel", count: 6)
        }
        let model = AppModel(metricsProvider: SnapshotQAMetricsProvider(value: snapshot))
        model.includeProcessNamesInReport = true
        model.includeVolumeNamesInReport = true
        await model.refreshAll()
        return model
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
        exit(EXIT_FAILURE)
    }
}

private struct SnapshotQAMetricsProvider: SystemMetricsProviding {
    let value: SystemSnapshot

    func snapshot() async -> SystemSnapshot {
        value
    }
}
