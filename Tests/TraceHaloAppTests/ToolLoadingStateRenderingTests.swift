import AppKit
import TraceHaloCore
import SwiftUI
import XCTest
@testable import TraceHaloApp

final class ToolLoadingStateRenderingTests: XCTestCase {
    func testStartupSkeletonUsesSevenRowsWithTheSameInventoryGeometry() {
        XCTAssertEqual(ToolLoadingLayout.startupPlaceholderRowCount, 7)
        XCTAssertEqual(ToolLoadingLayout.startupRowHeight, 74)
        XCTAssertEqual(
            ToolLoadingLayout.startupInventoryHeight,
            7 * 74 + 6,
            accuracy: 0.01
        )
        XCTAssertEqual(ToolLoadingLayout.applicationPlaceholderRowCount, 8)
        XCTAssertEqual(ToolLoadingLayout.searchFieldHeight, 42)
        XCTAssertFalse(ToolSkeletonMotionPolicy.animates(reduceMotion: true))
        XCTAssertTrue(ToolSkeletonMotionPolicy.animates(reduceMotion: false))
        XCTAssertEqual(
            ToolSkeletonMotionPolicy.opacity(reduceMotion: true, isBright: false),
            ToolSkeletonMotionPolicy.opacity(reduceMotion: true, isBright: true),
            "Reduce Motion 打开时不应保留任何脉冲明暗状态"
        )
        XCTAssertNotEqual(
            ToolSkeletonMotionPolicy.opacity(reduceMotion: false, isBright: false),
            ToolSkeletonMotionPolicy.opacity(reduceMotion: false, isBright: true)
        )
    }

    @MainActor
    func testStartupFirstLoadAndFailureRenderWithoutChangingCanvas() async throws {
        let size = CGSize(width: 1_180, height: 760)
        let loadingModel = AppModel(
            startupProvider: DelayedStartupProvider(delay: .seconds(30))
        )
        let loadingTask = Task { @MainActor in
            await loadingModel.loadStartupItemsIfNeeded()
        }
        await waitUntil { loadingModel.isLoadingStartupItems }

        let loading = try await render(
            OptimizerView().environment(loadingModel),
            size: size
        )
        loadingTask.cancel()
        await loadingTask.value

        let failureModel = AppModel(
            startupProvider: FailingToolStartupProvider(message: "fixture startup failure")
        )
        await failureModel.loadStartupItemsIfNeeded()
        let failure = try await render(
            OptimizerView().environment(failureModel),
            size: size
        )

        XCTAssertEqual(loading.size, size)
        XCTAssertEqual(failure.size, size)
        XCTAssertFalse(loading.bitmap.isEmpty)
        XCTAssertFalse(failure.bitmap.isEmpty)
        XCTAssertNotEqual(loading.bitmap, failure.bitmap)
    }

    @MainActor
    func testApplicationFirstLoadAndFailureRenderBothColumnsOnOneCanvas() async throws {
        let size = CGSize(width: 1_180, height: 760)
        let loadingModel = AppModel(
            applicationProvider: DelayedApplicationProvider(delay: .seconds(30))
        )
        let loadingTask = Task { @MainActor in
            await loadingModel.loadApplicationsIfNeeded()
        }
        await waitUntil { loadingModel.isLoadingApplications }

        let loading = try await render(
            UninstallerView().environment(loadingModel),
            size: size
        )
        loadingTask.cancel()
        await loadingTask.value

        let failureModel = AppModel(
            applicationProvider: FailingToolApplicationProvider(message: "fixture application failure")
        )
        await failureModel.loadApplicationsIfNeeded()
        let failure = try await render(
            UninstallerView().environment(failureModel),
            size: size
        )

        XCTAssertEqual(loading.size, size)
        XCTAssertEqual(failure.size, size)
        XCTAssertFalse(loading.bitmap.isEmpty)
        XCTAssertFalse(failure.bitmap.isEmpty)
        XCTAssertNotEqual(loading.bitmap, failure.bitmap)
    }

    @MainActor
    private func render<Content: View>(
        _ content: Content,
        size: CGSize
    ) async throws -> (size: CGSize, bitmap: Data) {
        let root = NavigationStack { content }
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

        await InMemoryHostingRenderer.settleUI(hostingView, milliseconds: 100)
        return (
            hostingView.bounds.size,
            try InMemoryHostingRenderer.bitmapData(for: hostingView)
        )
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(1),
        _ predicate: () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !predicate(), clock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(predicate(), "后台加载应在超时前开始")
    }
}

private struct DelayedStartupProvider: StartupItemProviding {
    let delay: Duration

    func items() async throws -> [StartupItem] {
        try await Task.sleep(for: delay)
        return []
    }
}

private struct DelayedApplicationProvider: ApplicationProviding {
    let delay: Duration

    func applications() async throws -> [ApplicationCandidate] {
        try await Task.sleep(for: delay)
        return []
    }
}

private struct ToolFixtureError: LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private struct FailingToolStartupProvider: StartupItemProviding {
    let message: String

    func items() async throws -> [StartupItem] {
        throw ToolFixtureError(message: message)
    }
}

private struct FailingToolApplicationProvider: ApplicationProviding {
    let message: String

    func applications() async throws -> [ApplicationCandidate] {
        throw ToolFixtureError(message: message)
    }
}
