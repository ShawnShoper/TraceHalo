import AppKit
import Foundation

@main
struct SnapshotQAMain {
    @MainActor
    static func main() async {
        guard let path = CommandLine.arguments.dropFirst().first, path.hasPrefix("/") else {
            print("Usage: TraceHaloSnapshotQA /absolute/output/directory")
            return
        }

        _ = NSApplication.shared
        let appIconPath = FileManager.default.currentDirectoryPath
            + "/.build/TraceHalo.app/Contents/Resources/AppIcon.icns"
        if let appIcon = NSImage(contentsOfFile: appIconPath) {
            NSApplication.shared.applicationIconImage = appIcon
        }
        let model = AppModel()
        model.monitorConfiguration = .standard
        await model.refreshAll()
        await model.preloadToolData()
        await model.loadSelectedApplicationDetails()
        do {
            try UISnapshotCapture.captureAll(
                model: model,
                outputDirectory: URL(fileURLWithPath: path, isDirectory: true)
            )
            print("Captured UI snapshots in \(path)")
        } catch {
            print("UI snapshot capture failed: \(error.localizedDescription)")
        }
    }
}
