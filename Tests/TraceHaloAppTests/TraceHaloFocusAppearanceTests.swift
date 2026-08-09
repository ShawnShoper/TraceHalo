import AppKit
import SwiftUI
import XCTest
@testable import TraceHaloApp

@MainActor
final class TraceHaloFocusAppearanceTests: XCTestCase {
    func testInterfaceRootSuppressesSystemFocusEffectForDescendants() async {
        var observedHiddenState = false
        let hostingView = NSHostingView(
            rootView: FocusAppearanceProbe { isHidden in
                observedHiddenState = isHidden
            }
            .traceHaloFocusAppearance()
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 160, height: 80)

        let window = NSWindow(
            contentRect: hostingView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderOut(nil)
        defer {
            window.contentView = nil
            window.close()
        }

        await InMemoryHostingRenderer.settleUI(hostingView)

        XCTAssertTrue(
            observedHiddenState,
            "TraceHalo 界面根节点必须向所有后代声明隐藏系统焦点外观"
        )
    }

    func testStatusButtonHidesFocusRingWithoutRemovingKeyboardFocus() throws {
        let button = NSButton(frame: NSRect(x: 0, y: 0, width: 120, height: 32))
        button.title = "TraceHalo"
        TraceHaloFocusAppearance.configureStatusButton(button)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 160, height: 80),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: window.contentLayoutRect)
        let contentView = try XCTUnwrap(window.contentView)
        contentView.addSubview(button)
        defer {
            window.contentView = nil
            window.close()
        }

        XCTAssertEqual(button.focusRingType, .none)
        XCTAssertTrue(button.acceptsFirstResponder)
        XCTAssertTrue(window.makeFirstResponder(button))
        XCTAssertTrue(window.firstResponder === button)
    }
}

private struct FocusAppearanceProbe: View {
    @Environment(\.traceHaloSystemFocusEffectIsHidden) private var isHidden
    let onResolve: (Bool) -> Void

    var body: some View {
        Button("刷新") {}
            .onAppear {
                onResolve(isHidden)
            }
    }
}
