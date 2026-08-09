import Foundation
import TraceHaloCore

enum StorageHealthSemanticCondition: Equatable, Sendable {
    case normal
    case warning
    case critical
    case unknown

    static func classify(_ health: StorageHealth) -> Self {
        guard health.availability.isAvailable else { return .unknown }
        let normalized = health.status?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        if [
            "failing", "failed", "failure", "poor", "bad",
            "not verified", "not good", "故障", "失败", "需要维护"
        ].contains(normalized) {
            return .critical
        }
        if ["warning", "caution", "警告", "注意"].contains(normalized) {
            return .warning
        }
        if ["verified", "smart verified", "good", "normal", "正常", "健康"].contains(normalized) {
            return .normal
        }
        return .unknown
    }
}

struct StorageIOHistorySample: Identifiable, Equatable, Sendable {
    let capturedAt: Date
    let readBytesPerSecond: Double
    let writeBytesPerSecond: Double
    let readOperationsPerSecond: Double
    let writeOperationsPerSecond: Double

    var id: Date { capturedAt }
}

enum StorageIOHistoryPolicy {
    static let windowDuration: TimeInterval = 60
    static let minimumSampleInterval: TimeInterval = 3
    static let capacity = 64

    static func sample(
        capturedAt: Date,
        storageIO: StorageIOState
    ) -> StorageIOHistorySample? {
        guard storageIO.availability.isAvailable,
              let readBytesPerSecond = storageIO.readBytesPerSecond,
              let writeBytesPerSecond = storageIO.writeBytesPerSecond,
              let readOperationsPerSecond = storageIO.readOperationsPerSecond,
              let writeOperationsPerSecond = storageIO.writeOperationsPerSecond
        else {
            return nil
        }

        let values = [
            readBytesPerSecond,
            writeBytesPerSecond,
            readOperationsPerSecond,
            writeOperationsPerSecond
        ]
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }

        return StorageIOHistorySample(
            capturedAt: capturedAt,
            readBytesPerSecond: readBytesPerSecond,
            writeBytesPerSecond: writeBytesPerSecond,
            readOperationsPerSecond: readOperationsPerSecond,
            writeOperationsPerSecond: writeOperationsPerSecond
        )
    }

    static func appending(
        _ sample: StorageIOHistorySample,
        to history: [StorageIOHistorySample]
    ) -> [StorageIOHistorySample]? {
        guard isValid(sample) else { return nil }
        guard let previous = history.last else { return [sample] }

        let elapsed = sample.capturedAt.timeIntervalSince(previous.capturedAt)
        if elapsed < 0 {
            // A wall-clock correction invalidates the old 60-second window.
            return [sample]
        }
        if elapsed == 0 {
            guard sample != previous else { return nil }
            var next = history
            next[next.count - 1] = sample
            return trimmed(next, at: sample.capturedAt)
        }

        guard sample.hasDifferentValues(from: previous)
                || elapsed >= minimumSampleInterval
        else {
            return nil
        }

        var next = history
        next.append(sample)
        return trimmed(next, at: sample.capturedAt)
    }

    private static func isValid(_ sample: StorageIOHistorySample) -> Bool {
        [
            sample.readBytesPerSecond,
            sample.writeBytesPerSecond,
            sample.readOperationsPerSecond,
            sample.writeOperationsPerSecond
        ].allSatisfy { $0.isFinite && $0 >= 0 }
    }

    private static func trimmed(
        _ history: [StorageIOHistorySample],
        at now: Date
    ) -> [StorageIOHistorySample] {
        let cutoff = now.addingTimeInterval(-windowDuration)
        let windowed = history.filter { sample in
            sample.capturedAt >= cutoff && sample.capturedAt <= now
        }
        return Array(windowed.suffix(capacity))
    }
}

private extension StorageIOHistorySample {
    func hasDifferentValues(from other: StorageIOHistorySample) -> Bool {
        readBytesPerSecond != other.readBytesPerSecond
            || writeBytesPerSecond != other.writeBytesPerSecond
            || readOperationsPerSecond != other.readOperationsPerSecond
            || writeOperationsPerSecond != other.writeOperationsPerSecond
    }
}
