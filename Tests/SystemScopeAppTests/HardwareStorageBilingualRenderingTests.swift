import AppKit
import SwiftUI
import XCTest
@testable import SystemScopeApp

final class HardwareStorageBilingualRenderingTests: XCTestCase {
    private let sizes = [
        CGSize(width: 1_180, height: 750),
        CGSize(width: 1_320, height: 840)
    ]
    private let locales = [Locale(identifier: "en"), Locale(identifier: "zh-Hans")]

    @MainActor
    func testHardwareAndStoragePagesRenderWithoutHorizontalCropping() async throws {
        for locale in locales {
            for size in sizes {
                for page in pages {
                    let rendered = try await render(
                        page.makeView(AppModel()),
                        locale: locale,
                        size: size
                    )

                    XCTAssertEqual(rendered.view.bounds.size.width, size.width, accuracy: 0.5)
                    XCTAssertEqual(rendered.view.bounds.size.height, size.height, accuracy: 0.5)
                    XCTAssertGreaterThan(
                        rendered.bitmap.count,
                        1_000,
                        "\(page.name) \(locale.identifier) \(size) should render in memory"
                    )

                    for scrollView in descendants(of: NSScrollView.self, in: rendered.view) {
                        XCTAssertFalse(
                            scrollView.hasHorizontalScroller,
                            "\(page.name) \(locale.identifier) \(size) must not expose a horizontal scroller"
                        )
                        guard let documentView = scrollView.documentView else { continue }
                        XCTAssertLessThanOrEqual(
                            documentView.bounds.width,
                            scrollView.contentView.bounds.width + 1,
                            "\(page.name) \(locale.identifier) \(size) content must not be clipped horizontally"
                        )
                    }
                }
            }
        }
    }

    @MainActor
    private func render(
        _ content: AnyView,
        locale: Locale,
        size: CGSize
    ) async throws -> (view: NSView, bitmap: Data) {
        let root = NavigationStack { content }
            .environment(\.locale, locale)
            .preferredColorScheme(.dark)
            .frame(width: size.width, height: size.height)
        let hostingView = NSHostingView(rootView: root)
        let frame = NSRect(origin: .zero, size: size)
        hostingView.frame = frame

        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = hostingView
        window.orderOut(nil)
        defer {
            window.contentView = nil
            window.close()
        }

        await InMemoryHostingRenderer.settleUI(hostingView, milliseconds: 80)
        return (
            hostingView,
            try InMemoryHostingRenderer.bitmapData(for: hostingView)
        )
    }

    @MainActor
    private func descendants<ViewType: NSView>(
        of type: ViewType.Type,
        in root: NSView
    ) -> [ViewType] {
        var matches = root.subviews.compactMap { $0 as? ViewType }
        for subview in root.subviews {
            matches.append(contentsOf: descendants(of: type, in: subview))
        }
        return matches
    }

    private var pages: [(name: String, makeView: (AppModel) -> AnyView)] {
        [
            ("graphics", { model in AnyView(GraphicsView().environment(model)) }),
            ("input devices", { model in AnyView(InputDevicesView().environment(model)) }),
            ("cooling", { model in AnyView(CoolingView().environment(model)) }),
            ("battery", { model in AnyView(BatteryView().environment(model)) }),
            ("storage", { model in AnyView(StorageView().environment(model)) })
        ]
    }
}
