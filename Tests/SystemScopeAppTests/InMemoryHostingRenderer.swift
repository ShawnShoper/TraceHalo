import AppKit
import XCTest

@MainActor
enum InMemoryHostingRenderer {
    static func settleUI(_ view: NSView, milliseconds: Int = 60) async {
        view.layoutSubtreeIfNeeded()
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(milliseconds))
        view.layoutSubtreeIfNeeded()
        await Task.yield()
    }

    static func bitmapData(for view: NSView, in requestedRect: NSRect? = nil) throws -> Data {
        view.layoutSubtreeIfNeeded()
        let captureRect = requestedRect ?? view.bounds

        XCTAssertFalse(captureRect.isEmpty, "内存截图区域不能为空")
        XCTAssertTrue(
            view.bounds.contains(captureRect),
            "内存截图区域必须位于视图边界内：\(captureRect) / \(view.bounds)"
        )

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: captureRect))
        view.cacheDisplay(in: captureRect, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}
