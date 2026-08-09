import Foundation
import Testing
@testable import TraceHaloApp

@Suite("Count localization")
struct AppCountLocalizationTests {
    private let english = Locale(identifier: "en")
    private let chinese = Locale(identifier: "zh-Hans")

    @Test("English uses singular only for one")
    func englishSingularAndPlural() {
        #expect(fanCount(1, locale: english) == "1 fan · Normal")
        #expect(fanCount(0, locale: english) == "0 fans · Normal")
        #expect(fanCount(2, locale: english) == "2 fans · Normal")
        #expect(applicationCount(1, locale: english) == "1 app")
        #expect(applicationCount(2, locale: english) == "2 apps")
        #expect(refreshDescription(1, locale: english) == "Updates every 1 second using This Mac Data.")
        #expect(refreshDescription(2, locale: english) == "Updates every 2 seconds using This Mac Data.")
        #expect(visibleCount(1, locale: english) == "1 item visible")
        #expect(visibleCount(2, locale: english) == "2 items visible")
    }

    @Test("Simplified Chinese remains natural for every count")
    func chineseDoesNotNeedNounInflection() {
        #expect(fanCount(1, locale: chinese) == "1 个风扇 · Normal")
        #expect(fanCount(2, locale: chinese) == "2 个风扇 · Normal")
        #expect(applicationCount(1, locale: chinese) == "1 个应用")
        #expect(applicationCount(2, locale: chinese) == "2 个应用")
    }

    @Test("Only the exact count one selects the singular key")
    func keySelection() {
        #expect(AppCountLocalization.key(count: 1, one: "one", other: "other") == "one")
        #expect(AppCountLocalization.key(count: 0, one: "one", other: "other") == "other")
        #expect(AppCountLocalization.key(count: 3, one: "one", other: "other") == "other")
    }

    private func fanCount(_ count: Int, locale: Locale) -> String {
        AppCountLocalization.format(
            count: count,
            oneKey: "dashboard.fan.count.one",
            otherKey: "dashboard.fan.count.other",
            oneDefaultValue: "%ld 个风扇 · %@",
            otherDefaultValue: "%ld 个风扇 · %@",
            locale: locale,
            count,
            "Normal"
        )
    }

    private func applicationCount(_ count: Int, locale: Locale) -> String {
        AppCountLocalization.format(
            count: count,
            oneKey: "tool.application.count.one",
            otherKey: "tool.application.count.other",
            oneDefaultValue: "%lld 个应用",
            otherDefaultValue: "%lld 个应用",
            locale: locale,
            Int64(count)
        )
    }

    private func refreshDescription(_ count: Int, locale: Locale) -> String {
        AppCountLocalization.format(
            count: count,
            oneKey: "monitor.refresh.description.one",
            otherKey: "monitor.refresh.description.other",
            oneDefaultValue: "每 %lld 秒读取一次状态；当前使用%@。",
            otherDefaultValue: "每 %lld 秒读取一次状态；当前使用%@。",
            locale: locale,
            Int64(count),
            "This Mac Data"
        )
    }

    private func visibleCount(_ count: Int, locale: Locale) -> String {
        AppCountLocalization.format(
            count: count,
            oneKey: "monitor.visible.count.one",
            otherKey: "monitor.visible.count.other",
            oneDefaultValue: "当前显示 %lld 项",
            otherDefaultValue: "当前显示 %lld 项",
            locale: locale,
            Int64(count)
        )
    }
}
