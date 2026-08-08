import Foundation
import Testing
@testable import SystemScopeCore

@Suite("Core localization")
struct LocalizationTests {
    @Test("Runtime locale resolution is pure and defaults to system")
    func runtimeLocaleResolution() {
        #expect(
            TraceHaloLocalization.resolvedLocale(
                storedPreferenceRawValue: nil,
                preferredLanguages: ["zh-Hans-CN"]
            ).identifier == "zh-Hans"
        )
        #expect(
            TraceHaloLocalization.resolvedLocale(
                storedPreferenceRawValue: "unsupported-value",
                preferredLanguages: ["fr-FR"]
            ).identifier == "en"
        )
        #expect(
            TraceHaloLocalization.resolvedLocale(
                storedPreferenceRawValue: "zh-Hans",
                preferredLanguages: ["en-US"]
            ).identifier == "zh-Hans"
        )
    }

    @Test("Core resources resolve in both supported languages")
    func coreResources() {
        #expect(
            TraceHaloLocalization.string(
                "core.localization.test.plain",
                defaultValue: "Missing",
                locale: Locale(identifier: "en")
            ) == "English Core Value"
        )
        #expect(
            TraceHaloLocalization.string(
                "core.localization.test.plain",
                defaultValue: "缺失",
                locale: Locale(identifier: "zh-Hans")
            ) == "中文核心文案"
        )
    }

    @Test("Formatted dynamic strings use the requested locale resource")
    func formattedResources() {
        #expect(
            TraceHaloLocalization.format(
                "core.localization.test.formatted",
                defaultValue: "%@ has %ld items",
                locale: Locale(identifier: "en"),
                "Disk", 3
            ) == "Disk has 3 items"
        )
        #expect(
            TraceHaloLocalization.format(
                "core.localization.test.formatted",
                defaultValue: "%@ 有 %ld 项",
                locale: Locale(identifier: "zh-Hans"),
                "磁盘", 3
            ) == "磁盘 有 3 项"
        )
    }

    @Test("Unsupported explicit locales use English resources")
    func unsupportedExplicitLocale() {
        #expect(
            TraceHaloLocalization.string(
                "core.localization.test.plain",
                defaultValue: "Missing",
                locale: Locale(identifier: "de-DE")
            ) == "English Core Value"
        )
    }

    @Test("Semantic startup scopes stay stable while their labels localize")
    func startupScopeSemantics() {
        let item = StartupItem(
            label: "com.example.agent",
            displayName: "Agent",
            kind: .launchAgent,
            path: "/Users/example/Library/LaunchAgents/com.example.agent.plist",
            isEnabled: true,
            scopeKind: .currentUser
        )

        #expect(item.scopeKind == .currentUser)
        #expect(
            item.scopeKind.localizedTitle(locale: Locale(identifier: "en"))
                == "Current User"
        )
        #expect(
            item.scopeKind.localizedTitle(locale: Locale(identifier: "zh-Hans"))
                == "当前用户"
        )
    }

    @Test("Monitor and associated-file semantics localize without changing IDs")
    func semanticPresentation() {
        #expect(
            MonitorModule.storage.localizedTitle(locale: Locale(identifier: "en"))
                == "Storage"
        )
        #expect(
            MonitorModule.storage.localizedTitle(locale: Locale(identifier: "zh-Hans"))
                == "存储"
        )
        #expect(
            AssociatedFileCategory.preference.localizedTitle(locale: Locale(identifier: "en"))
                == "Preferences"
        )
        #expect(
            AssociatedFileCategory.preference.localizedTitle(locale: Locale(identifier: "zh-Hans"))
                == "偏好设置"
        )
    }

    @Test("Legacy storage labels map to stable semantic metric kinds")
    func storageMetricSemantics() {
        #expect(StorageHealthMetric(name: "设备", value: "disk3").kind == .device)
        #expect(StorageHealthMetric(name: "Connection", value: "USB").kind == .connection)
        #expect(StorageHealthMetric(name: "Vendor Value", value: "x").kind == nil)
    }

    @Test("Dynamic errors can render deterministically in either language")
    func localizedErrors() {
        let violation = SafetyViolation.deniedInSafeTestMode(.uninstall)
        #expect(
            violation.localizedDescription(locale: Locale(identifier: "en"))
                == "Safe Test Mode blocked the uninstall operation."
        )
        #expect(
            violation.localizedDescription(locale: Locale(identifier: "zh-Hans"))
                == "安全测试模式已阻止卸载操作。"
        )
        #expect(
            SMCReadError.invalidKey("TC0P")
                .localizedDescription(locale: Locale(identifier: "en"))
                == "Invalid SMC key: TC0P."
        )
        #expect(
            SMCReadError.invalidKey("TC0P")
                .localizedDescription(locale: Locale(identifier: "zh-Hans"))
                == "SMC key 无效：TC0P。"
        )
    }

    @Test("Duration formatting follows the selected app language")
    func localizedDurations() {
        #expect(
            MetricFormatter.duration(
                90_000,
                locale: Locale(identifier: "en")
            ) == "1 d 1 hr"
        )
        #expect(
            MetricFormatter.duration(
                90_000,
                locale: Locale(identifier: "zh-Hans")
            ) == "1 天 1 小时"
        )
    }

    @Test("Partial uninstall uses English singular and plural nouns")
    func localizedPartialUninstallCounts() {
        let singular = UninstallExecutionError.partialCompletion(
            moved: 0,
            total: 1,
            reason: "Permission denied"
        ).localizedDescription(locale: Locale(identifier: "en"))
        let plural = UninstallExecutionError.partialCompletion(
            moved: 1,
            total: 2,
            reason: "Permission denied"
        ).localizedDescription(locale: Locale(identifier: "en"))

        #expect(
            singular
                == "Moved 0 of 1 item to the Trash, then stopped: Permission denied. Items already moved can be restored from the Trash."
        )
        #expect(
            plural
                == "Moved 1 of 2 items to the Trash, then stopped: Permission denied. Items already moved can be restored from the Trash."
        )
    }

    @Test("System reports render complete English and Chinese structures")
    func localizedSystemReports() {
        let builder = SystemReportBuilder()
        let options = SystemReportOptions(
            includeProcessNames: false,
            includeVolumeNames: false
        )
        let english = builder.text(
            snapshot: .fixture,
            options: options,
            locale: Locale(identifier: "en")
        )
        let chinese = builder.text(
            snapshot: .fixture,
            options: options,
            locale: Locale(identifier: "zh-Hans")
        )

        #expect(english.contains("TraceHalo System Report"))
        #expect(english.contains("[Hardware]"))
        #expect(english.contains("Input devices:"))
        #expect(!english.contains("[硬件]"))
        #expect(chinese.contains("TraceHalo 系统报告"))
        #expect(chinese.contains("[硬件]"))
        #expect(chinese.contains("输入设备："))
        #expect(!chinese.contains("[Hardware]"))
    }
}
