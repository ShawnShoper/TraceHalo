import AppKit
import SwiftUI

#if SNAPSHOT_QA
@MainActor
enum UISnapshotCapture {
    private struct Target {
        let name: String
        let view: AnyView
        let size: CGSize
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
        outputDirectory: URL
    ) throws {
        try verifyMenuBarIntrinsicSize(model: model, initialSection: nil)
        for section in MenuBarDashboardSection.referenceOrder {
            try verifyMenuBarIntrinsicSize(model: model, initialSection: section)
        }
        try verifyStatusBarIntrinsicSize(model: model)

        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )

        let pageSize = CGSize(width: 1_220, height: 790)
        let monitorReferenceSize = CGSize(width: 1_558, height: 1_010)
        let storageReferenceSize = CGSize(width: 1_558, height: 1_010)
        let settingsReferenceSize = CGSize(width: 1_558, height: 1_010)
        let aboutReferenceSize = CGSize(width: 980, height: 624)
        var targets = [
            Target(
                name: "00-system-map-overview",
                view: wrappedRoot(model: model, destination: .dashboard, size: pageSize),
                size: pageSize
            ),
            Target(name: "01-dashboard", view: wrapped(DashboardView(), model: model), size: pageSize),
            Target(
                name: "02-monitor",
                view: wrappedRoot(
                    model: model,
                    destination: .monitor,
                    size: monitorReferenceSize
                ),
                size: monitorReferenceSize
            ),
            Target(name: "03-optimizer", view: wrapped(OptimizerView(), model: model), size: pageSize),
            Target(name: "04-uninstaller", view: wrapped(UninstallerView(), model: model), size: pageSize),
            Target(
                name: "05-storage",
                view: wrappedRoot(
                    model: model,
                    destination: .storage,
                    size: storageReferenceSize
                ),
                size: storageReferenceSize
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

        for target in targets {
            let frame = NSRect(origin: .zero, size: target.size)
            let hostingView = NSHostingView(rootView: target.view)
            hostingView.frame = frame
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.isReleasedWhenClosed = false
            window.contentView = hostingView
            window.orderOut(nil)
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            hostingView.layoutSubtreeIfNeeded()

            guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: frame) else {
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
            window.contentView = nil
            window.close()
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

    private static func wrappedRoot(
        model: AppModel,
        destination: AppDestination,
        size: CGSize
    ) -> AnyView {
        let router = AppNavigationRouter(destination: destination)
        return AnyView(
            RootView()
                .environment(model)
                .environment(router)
                .environment(\.locale, AppLocalization.currentLocale)
                .frame(width: size.width, height: size.height)
                .background(Color(nsColor: .windowBackgroundColor))
                .preferredColorScheme(.dark)
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
#endif
