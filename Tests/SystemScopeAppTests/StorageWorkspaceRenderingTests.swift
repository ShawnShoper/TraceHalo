import AppKit
import SwiftUI
import XCTest
@testable import SystemScopeApp
import SystemScopeCore

final class StorageWorkspaceRenderingTests: XCTestCase {
    private let defaultWindowSize = CGSize(width: 1_320, height: 840)
    private let compactContentSize = CGSize(
        width: 1_180 - SidebarLayout.width,
        height: 700
    )

    @MainActor
    func testStorageWorkspaceRendersInsideDefaultRootLayoutWithSidebar() async throws {
        let model = AppModel()
        let router = AppNavigationRouter(destination: .storage)

        let rendered = try await render(
            RootView()
                .environment(model)
                .environment(router),
            at: defaultWindowSize
        )

        XCTAssertEqual(rendered.size.width, defaultWindowSize.width, accuracy: 0.5)
        XCTAssertEqual(rendered.size.height, defaultWindowSize.height, accuracy: 0.5)
        XCTAssertGreaterThan(rendered.bitmap.count, 1_000)
    }

    @MainActor
    func testStorageViewFitsCompactContentWidthWithoutHorizontalCropping() async throws {
        let rendered = try await render(
            StorageView().environment(AppModel()),
            at: compactContentSize
        )

        XCTAssertEqual(rendered.size.width, compactContentSize.width, accuracy: 0.5)
        XCTAssertEqual(rendered.size.height, compactContentSize.height, accuracy: 0.5)
        XCTAssertGreaterThan(rendered.bitmap.count, 1_000)

        let scrollViews = descendants(of: NSScrollView.self, in: rendered.hostingView)
        XCTAssertFalse(scrollViews.isEmpty, "存储页应保留纵向滚动容器")

        for scrollView in scrollViews {
            XCTAssertFalse(scrollView.hasHorizontalScroller, "紧凑宽度不应产生横向滚动条")
            guard let documentView = scrollView.documentView else { continue }
            XCTAssertLessThanOrEqual(
                documentView.bounds.width,
                scrollView.contentView.bounds.width + 1,
                "存储页内容宽度不能超出可见区域后被裁剪"
            )
        }
    }

    @MainActor
    func testStorageIORendersWithNoHistoryAndWithPopulatedHistory() async throws {
        let emptyHistoryModel = AppModel()
        XCTAssertTrue(emptyHistoryModel.storageIOHistory.isEmpty)

        let emptyHistoryRender = try await render(
            StorageView().environment(emptyHistoryModel),
            at: compactContentSize
        )
        XCTAssertGreaterThan(emptyHistoryRender.bitmap.count, 1_000)

        let start = Date(timeIntervalSince1970: 10_000)
        let provider = StorageRenderingMetricsProvider(
            snapshots: [
                storageSnapshot(at: start, read: 12_000_000, write: 5_000_000),
                storageSnapshot(
                    at: start.addingTimeInterval(4),
                    read: 54_000_000,
                    write: 19_000_000
                )
            ]
        )
        let populatedHistoryModel = AppModel(metricsProvider: provider)
        await populatedHistoryModel.refreshAll()
        await populatedHistoryModel.refreshAll()
        XCTAssertEqual(populatedHistoryModel.storageIOHistory.count, 2)

        let populatedHistoryRender = try await render(
            StorageView().environment(populatedHistoryModel),
            at: compactContentSize
        )
        XCTAssertGreaterThan(populatedHistoryRender.bitmap.count, 1_000)
        XCTAssertNotEqual(emptyHistoryRender.bitmap, populatedHistoryRender.bitmap)
    }

    @MainActor
    private func render<Content: View>(
        _ content: Content,
        at size: CGSize
    ) async throws -> (size: CGSize, bitmap: Data, hostingView: NSView) {
        let rootView = content
            .preferredColorScheme(.dark)
            .frame(width: size.width, height: size.height)
        let hostingView = NSHostingView(rootView: rootView)
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

        await InMemoryHostingRenderer.settleUI(hostingView, milliseconds: 100)
        return (
            hostingView.bounds.size,
            try InMemoryHostingRenderer.bitmapData(for: hostingView),
            hostingView
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

    private func storageSnapshot(
        at date: Date,
        read: Double,
        write: Double
    ) -> SystemSnapshot {
        var snapshot = SystemSnapshot.fixture
        snapshot.capturedAt = date
        snapshot.storageIO = StorageIOState(
            availability: .available,
            totalReadBytes: 4_024_514_007_040,
            totalWrittenBytes: 3_225_660_510_208,
            totalReadOperations: 464_327_179,
            totalWriteOperations: 149_019_979,
            readBytesPerSecond: read,
            writeBytesPerSecond: write,
            readOperationsPerSecond: 1_240,
            writeOperationsPerSecond: 690,
            deviceNames: ["APPLE SSD AP1024R Media"]
        )
        return snapshot
    }
}

private actor StorageRenderingMetricsProvider: SystemMetricsProviding {
    private let snapshots: [SystemSnapshot]
    private var nextIndex = 0

    init(snapshots: [SystemSnapshot]) {
        self.snapshots = snapshots
    }

    func snapshot() async -> SystemSnapshot {
        guard !snapshots.isEmpty else { return .fixture }
        let index = min(nextIndex, snapshots.count - 1)
        nextIndex += 1
        return snapshots[index]
    }
}
