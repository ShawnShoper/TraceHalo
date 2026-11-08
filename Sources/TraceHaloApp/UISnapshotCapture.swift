import AppKit
import SwiftUI
import TraceHaloCore

#if SNAPSHOT_QA
@MainActor
enum UISnapshotCapture {
    private struct Target {
        let name: String
        let view: AnyView
        let size: CGSize
        var appearance: NSAppearance.Name?
    }

    struct CaptureError: LocalizedError {
        let name: String

        var errorDescription: String? {
            "无法生成 \(name) 的界面快照。"
        }
    }

    struct MenuBarSizingError: LocalizedError {
        let state: String
        let actualSize: CGSize

        var errorDescription: String? {
            "菜单栏\(state)态固有尺寸异常：\(Int(actualSize.width)) × \(Int(actualSize.height))。"
        }
    }

    struct StatusBarSizingError: LocalizedError {
        let actualSize: CGSize

        var errorDescription: String? {
            "菜单栏状态区固有尺寸异常：\(Int(actualSize.width)) × \(Int(actualSize.height))。"
        }
    }

    static func captureAll(
        model: AppModel,
        portableSettingsModel: AppModel,
        reportRegressionModel: AppModel,
        outputDirectory: URL
    ) async throws {
        try verifyMenuBarIntrinsicSize(model: model, initialSection: nil)
        for section in MenuBarDashboardSection.referenceOrder {
            try verifyMenuBarIntrinsicSize(model: model, initialSection: section)
        }
        try verifyStatusBarIntrinsicSize(model: model)

        let pageSize = CGSize(width: 1_220, height: 790)
        let homeSize = CGSize(width: 1_320, height: 840)
        let minimumHomeSize = CGSize(width: 1_180, height: 700)
        let compactHomeSize = CGSize(width: 900, height: 700)
        let monitorReferenceSize = CGSize(width: 1_558, height: 1_010)
        let storageReferenceSize = CGSize(width: 1_558, height: 1_010)
        let settingsReferenceSize = CGSize(width: 1_558, height: 1_010)
        let aboutReferenceSize = CGSize(width: 980, height: 624)
        var targets = [
            rootTarget(
                name: "00-system-map-overview",
                model: model,
                size: homeSize
            ),
            rootTarget(name: "01-dashboard", model: model, size: homeSize),
            rootTarget(name: "01-live-home-minimum", model: model, size: minimumHomeSize),
            rootTarget(name: "01-live-home-compact", model: model, size: compactHomeSize),
            rootTarget(name: "01-live-home-light-en", model: model, size: homeSize, locale: Locale(identifier: "en")),
            rootTarget(name: "01-live-home-dark", model: model, size: homeSize, colorScheme: .dark),
            rootTarget(
                name: "02-monitor",
                model: model,
                size: monitorReferenceSize,
                workspace: .menuBarLayout
            ),
            rootTarget(
                name: "02-monitor-light-en",
                model: model,
                size: monitorReferenceSize,
                workspace: .menuBarLayout,
                locale: Locale(identifier: "en")
            ),
            Target(name: "03-optimizer", view: wrapped(OptimizerView(), model: model), size: pageSize),
            Target(name: "04-uninstaller", view: wrapped(UninstallerView(), model: model), size: pageSize),
            rootTarget(
                name: "04-uninstaller-light", model: model,
                size: CGSize(width: 1_440, height: 1_024), destination: .uninstaller
            ),
            rootTarget(
                name: "04-uninstaller-compact", model: model,
                size: CGSize(width: 1_000, height: 700), destination: .uninstaller
            ),
            rootTarget(
                name: "04-uninstaller-light-en", model: model,
                size: CGSize(width: 1_000, height: 700), destination: .uninstaller,
                locale: Locale(identifier: "en")
            ),
            rootTarget(
                name: "05-storage",
                model: model,
                size: storageReferenceSize,
                destination: .storage,
                colorScheme: .dark
            ),
            Target(name: "06-graphics", view: wrapped(GraphicsView(), model: model), size: pageSize),
            Target(name: "07-cooling", view: wrapped(CoolingView(), model: model), size: pageSize),
            Target(name: "08-battery", view: wrapped(BatteryView(), model: model), size: pageSize),
            Target(name: "08-input-devices", view: wrapped(InputDevicesView(), model: model), size: pageSize),
            Target(name: "09-report", view: wrapped(ReportView(), model: model), size: pageSize),
            Target(
                name: "10-settings",
                view: wrappedSettings(
                    model: portableSettingsModel,
                    size: settingsReferenceSize,
                    locale: Locale(identifier: "zh-Hans"),
                    colorScheme: .dark
                ),
                size: settingsReferenceSize
            ),
            Target(
                name: "10-settings-no-battery",
                view: wrappedSettings(
                    model: model,
                    size: settingsReferenceSize,
                    locale: Locale(identifier: "zh-Hans"),
                    colorScheme: .dark
                ),
                size: settingsReferenceSize
            ),
            Target(
                name: "10-settings-light-en",
                view: wrappedSettings(
                    model: portableSettingsModel,
                    size: settingsReferenceSize,
                    locale: Locale(identifier: "en"),
                    colorScheme: .light
                ),
                size: settingsReferenceSize
            ),
            Target(
                name: "10-settings-about",
                view: wrappedAbout(
                    model: portableSettingsModel,
                    size: aboutReferenceSize,
                    locale: Locale(identifier: "zh-Hans"),
                    colorScheme: .dark
                ),
                size: aboutReferenceSize
            ),
            Target(
                name: "11-menu-bar-dashboard",
                view: wrappedMenuBarDashboard(model: model, initialSection: nil),
                size: CGSize(
                    width: MenuBarDashboardLayout.collapsedContentWidth,
                    height: MenuBarDashboardLayout.maximumColumnHeight
                        + (MenuBarDashboardLayout.verticalChrome * 2)
                )
            ),
            Target(
                name: "12-menu-bar-status-strip",
                view: wrappedMenuBarStatusStrip(model: model),
                size: CGSize(width: 238, height: 30)
            )
        ]

        for section in [MenuBarDashboardSection.cpu, .memory, .network, .fans, .battery] {
            targets.append(rootTarget(
                name: "01-live-detail-\(section.rawValue)",
                model: section == .battery ? portableSettingsModel : model,
                size: homeSize,
                workspace: .live(section)
            ))
        }

        for (offset, section) in MenuBarDashboardSection.referenceOrder.enumerated() {
            targets.append(
                Target(
                    name: String(format: "%02d-menu-bar-detail-%@", 13 + offset, section.rawValue),
                    view: wrappedMenuBarDashboard(model: model, initialSection: section),
                    size: CGSize(
                        width: MenuBarDashboardLayout.expandedContentWidth,
                        height: MenuBarDashboardLayout.maximumColumnHeight
                            + (MenuBarDashboardLayout.verticalChrome * 2)
                    )
                )
            )
        }

        targets.append(contentsOf: reportRegressionTargets(model: reportRegressionModel))
        try await capture(targets, outputDirectory: outputDirectory)
        try await captureUninstallPermissions(outputDirectory: outputDirectory)
    }

    static func captureUninstallPermissions(outputDirectory: URL) async throws {
        var targets: [Target] = []
        let states: [(String, UninstallHelperSetupState, Bool, Bool)] = [
            ("not-configured", .notEnabled, false, false),
            ("approval-pending", .awaitingApproval, false, false),
            ("update-required", .updateRequired, false, false),
            ("disk-denied", .enabled, true, false),
            ("check-failed", .enabled, false, true),
            ("ready", .enabled, false, false)
        ]
        let suite = "TraceHalo-permission-snapshots-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for language in ["zh-Hans", "en"] {
            for (name, helper, denied, failed) in states {
                let service = PermissionSnapshotService(helperState: helper, denied: denied, failed: failed,
                    failureMessage: language == "en" ? "Could not verify access. Try checking again." : "暂时无法检查访问权限，请重新检查。")
                let controller = UninstallPermissionController(service: service, defaults: defaults)
                await controller.refresh()
                let view = UninstallPermissionSetupView(controller: controller)
                    .environment(\.locale, Locale(identifier: language))
                    .preferredColorScheme(.light)
                targets.append(Target(name: "21-permissions-\(name)-\(language)", view: AnyView(view),
                    size: CGSize(width: 660, height: 610), appearance: .aqua))
            }
        }
        try await capture(targets, outputDirectory: outputDirectory)
    }

    static func captureReportRegression(model: AppModel, outputDirectory: URL) async throws {
        try await capture(reportRegressionTargets(model: model), outputDirectory: outputDirectory)
    }

    static func captureDataReview(outputDirectory: URL) async throws {
        let model = AppModel()
        var application = FixtureCatalog.applications[0]
        application.associatedFiles.append(AssociatedFile(
            path: "~/Library/Containers/com.example.SampleStudio", category: .container,
            sizeBytes: 200_000_000, ownershipReason: "Fixture: identifier match",
            matchBasis: .exactBundleIdentifier("com.example.SampleStudio")))
        application.associatedFiles.append(AssociatedFile(
            path: "~/Library/Group Containers/team.shared", category: .groupContainer,
            ownershipReason: "Fixture: signed app group", matchBasis: .appGroup("team.shared"), retentionReason: .shared))
        application.dataDiscovery = ApplicationDataDiscoverySummary()
        application.dataDiscovery?.signatureVerified = true
        application.dataDiscovery?.signedComponentCount = 2
        application.dataDiscovery?.scriptCount = 5
        application.dataDiscovery?.receiptCount = 1
        var targets: [Target] = []
        for language in ["zh-Hans", "en"] {
            for mode in ["keep", "clean", "all-selected"] {
                var selection = ApplicationRemovalSelection()
                if mode != "keep" { selection.dataMode = .clean }
                if mode == "all-selected" { selection.toggleBulkSelection(for: application) }
                let view = ScrollView {
                    RemovalConfirmationView(application: application, initialSelection: selection,
                        onCancel: {}, onConfirm: { _ in })
                        .padding(20)
                }
                .background(CalmTheme.canvas)
                .preferredColorScheme(.light)
                .environment(model)
                .environment(\.locale, Locale(identifier: language))
                targets.append(Target(name: "data-review-\(mode)-\(language)",
                    view: AnyView(view), size: CGSize(width: 720, height: 640), appearance: .aqua))
                if mode == "all-selected" {
                    targets.append(Target(name: "data-review-final-\(language)",
                        view: AnyView(RemovalFinalConfirmationView(plan: selection.makePlan(for: application), onCancel: {}, onConfirm: {})
                            .environment(\.locale, Locale(identifier: language))
                            .preferredColorScheme(.light)),
                        size: CGSize(width: 660, height: 610), appearance: .aqua))
                }
            }
        }
        try await capture(targets, outputDirectory: outputDirectory)
    }

    private static func reportRegressionTargets(model: AppModel) -> [Target] {
        let sizes = [
            (name: "standard", size: CGSize(width: 1_320, height: 840)),
            (name: "compact", size: CGSize(width: 1_180, height: 750))
        ]
        return sizes.flatMap { viewport in
            ["zh-Hans", "en"].map { language in
                rootTarget(
                    name: "09-report-long-lines-\(viewport.name)-\(language)",
                    model: model,
                    size: viewport.size,
                    destination: .report,
                    locale: Locale(identifier: language)
                )
            }
        }
    }

    private static func capture(_ targets: [Target], outputDirectory: URL) async throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        for target in targets {
            let frame = NSRect(origin: .zero, size: target.size)
            let hostingView = NSHostingView(
                rootView: target.view.frame(width: target.size.width, height: target.size.height)
            )
            hostingView.sizingOptions = []
            hostingView.frame = frame
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            if let appearance = target.appearance {
                window.appearance = NSAppearance(named: appearance)
            }
            window.contentView = hostingView
            window.orderOut(nil)
            defer {
                window.contentView = nil
                window.close()
            }
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
            try await Task.sleep(for: .milliseconds(200))
            hostingView.layoutSubtreeIfNeeded()
            await Task.yield()
            hostingView.layoutSubtreeIfNeeded()

            guard hostingView.bounds.size == frame.size,
                  let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: frame) else {
                throw CaptureError(name: target.name)
            }
            hostingView.cacheDisplay(in: frame, to: bitmap)
            guard let data = bitmap.representation(using: .png, properties: [:]) else {
                throw CaptureError(name: target.name)
            }
            try data.write(
                to: outputDirectory.appendingPathComponent("\(target.name).png"),
                options: .atomic
            )
        }
    }

    private static func wrapped<Content: View>(_ content: Content, model: AppModel) -> AnyView {
        let router = AppNavigationRouter(destination: .dashboard)
        return AnyView(
            NavigationStack { content }
                .environment(model)
                .environment(router)
                .environment(\.locale, AppLocalization.currentLocale)
                .frame(width: 1_220, height: 790)
                .background(Color(nsColor: .windowBackgroundColor))
                .preferredColorScheme(.dark)
        )
    }

    private static func wrappedSettings(
        model: AppModel,
        size: CGSize,
        locale: Locale,
        colorScheme: ColorScheme
    ) -> AnyView {
        let router = AppNavigationRouter(destination: .settings)
        return AnyView(
            NavigationStack { SettingsView(isStandalone: true) }
                .environment(model)
                .environment(router)
                .environment(\.locale, locale)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .preferredColorScheme(colorScheme)
        )
    }

    private static func wrappedAbout(
        model: AppModel,
        size: CGSize,
        locale: Locale,
        colorScheme: ColorScheme
    ) -> AnyView {
        let iconPath = FileManager.default.currentDirectoryPath
            + "/Xcode/TraceHalo/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png"
        let appIcon = NSImage(contentsOfFile: iconPath)
            ?? NSApplication.shared.applicationIconImage
            ?? NSImage(size: NSSize(width: 1_024, height: 1_024))
        return AnyView(
            SettingsAboutSheet(
                metadata: .snapshotFixture,
                appIcon: appIcon
            )
                .environment(model)
                .environment(\.locale, locale)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .preferredColorScheme(colorScheme)
        )
    }

    private static func rootTarget(
        name: String,
        model: AppModel,
        size: CGSize,
        destination: AppDestination = .dashboard,
        workspace: MonitorWorkspace? = nil,
        locale: Locale = AppLocalization.currentLocale,
        colorScheme: ColorScheme = .light
    ) -> Target {
        let router = AppNavigationRouter(destination: destination)
        if let workspace {
            router.openMonitor(workspace)
        }
        let view = AnyView(
            RootView()
                .environment(model)
                .environment(router)
                .environment(\.locale, locale)
                .environment(\.colorScheme, colorScheme)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .preferredColorScheme(colorScheme)
        )
        return Target(
            name: name,
            view: view,
            size: size,
            appearance: colorScheme == .dark ? .darkAqua : .aqua
        )
    }

    private static func wrappedMenuBarDashboard(
        model: AppModel,
        initialSection: MenuBarDashboardSection?
    ) -> AnyView {
        let router = AppNavigationRouter(destination: .dashboard)
        return AnyView(
            MenuBarDashboardView(
                initialSection: initialSection
            )
                .environment(model)
                .environment(router)
                .environment(\.locale, AppLocalization.currentLocale)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 0.75)
                }
                .preferredColorScheme(.dark)
        )
    }

    private static func verifyMenuBarIntrinsicSize(
        model: AppModel,
        initialSection: MenuBarDashboardSection?
    ) throws {
        let hostingView = NSHostingView(
            rootView: wrappedMenuBarDashboard(
                model: model,
                initialSection: initialSection
            )
        )
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let expectedWidth = initialSection == nil
            ? MenuBarDashboardLayout.collapsedContentWidth
            : MenuBarDashboardLayout.expandedContentWidth

        guard abs(size.width - expectedWidth) <= 0.5, size.height >= 450 else {
            throw MenuBarSizingError(
                state: initialSection.map { "\($0.title)详情" } ?? "折叠",
                actualSize: size
            )
        }
    }

    private static func verifyStatusBarIntrinsicSize(model: AppModel) throws {
        let hostingView = NSHostingView(
            rootView: MenuBarStatusStrip()
                .environment(model)
                .environment(\.locale, AppLocalization.currentLocale)
                .preferredColorScheme(.dark)
        )
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize

        guard size.width >= 200, size.width <= 280, size.height >= 20, size.height <= 24 else {
            throw StatusBarSizingError(actualSize: size)
        }
    }

    private static func wrappedMenuBarStatusStrip(model: AppModel) -> AnyView {
        AnyView(
            MenuBarStatusStrip()
                .environment(model)
                .environment(\.locale, AppLocalization.currentLocale)
                .padding(.horizontal, 6)
                .frame(height: 30, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)
                .background(Color(nsColor: .windowBackgroundColor))
                .preferredColorScheme(.dark)
        )
    }

}

@MainActor
private struct PermissionSnapshotService: UninstallPermissionServicing {
    var helperState: UninstallHelperSetupState
    var denied: Bool
    var failed: Bool
    var failureMessage: String
    func requestHelper() async throws {}
    func checkTrashAccess() async throws {
        if failed { throw NSError(domain: "PermissionSnapshot", code: 1, userInfo: [NSLocalizedDescriptionKey: failureMessage]) }
        if denied { throw PrivilegedUninstallClientError.trashAccessDenied }
    }
    func openDiskSettings() {}
}
#endif
