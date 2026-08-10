import Foundation

enum DashboardHistoryRetention: Int, CaseIterable, Identifiable, Codable, Sendable {
    case threeDays = 3
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    static let storageKey = "dashboardHistoryRetentionDays"
    static let defaultValue = DashboardHistoryRetention.threeDays

    var id: Int { rawValue }
    var duration: TimeInterval { TimeInterval(rawValue) * 24 * 60 * 60 }
}

struct DashboardHistoryLoadResult: Equatable, Sendable {
    let samples: [DashboardTelemetrySample]

    var lastPersistedAt: Date? { samples.last?.date }
}

protocol DashboardHistoryPersisting: Sendable {
    func load(
        retention: DashboardHistoryRetention,
        now: Date
    ) async -> DashboardHistoryLoadResult

    func record(
        _ sample: DashboardTelemetrySample,
        retention: DashboardHistoryRetention,
        now: Date
    ) async

    func updateRetention(
        _ retention: DashboardHistoryRetention,
        now: Date
    ) async -> DashboardHistoryLoadResult
}

struct DisabledDashboardHistoryStore: DashboardHistoryPersisting {
    func load(
        retention _: DashboardHistoryRetention,
        now _: Date
    ) async -> DashboardHistoryLoadResult {
        DashboardHistoryLoadResult(samples: [])
    }

    func record(
        _: DashboardTelemetrySample,
        retention _: DashboardHistoryRetention,
        now _: Date
    ) async {}

    func updateRetention(
        _: DashboardHistoryRetention,
        now _: Date
    ) async -> DashboardHistoryLoadResult {
        DashboardHistoryLoadResult(samples: [])
    }
}

actor DashboardHistoryStore: DashboardHistoryPersisting {
    static let persistenceSampleInterval: TimeInterval = 60
    static let maximumPersistedSampleCount = 43_200
    static let hardDirectoryByteLimit = 16 * 1_024 * 1_024

    private struct Archive: Codable {
        static let currentVersion = 1

        let version: Int
        let samples: [DashboardTelemetrySample]

        init(samples: [DashboardTelemetrySample]) {
            version = Self.currentVersion
            self.samples = samples
        }
    }

    private static let filePrefix = "dashboard-history-"
    private static let fileSuffix = ".plist"
    private let directoryURL: URL
    private let fileManager: FileManager
    private let maximumSampleCount: Int
    private let hardByteLimit: Int
    private var cachedSamples: [DashboardTelemetrySample] = []
    private var hasLoaded = false

    init(
        directoryURL: URL = DashboardHistoryStore.defaultDirectoryURL(),
        fileManager: FileManager = .default,
        maximumSampleCount: Int = DashboardHistoryStore.maximumPersistedSampleCount,
        hardByteLimit: Int = DashboardHistoryStore.hardDirectoryByteLimit
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.maximumSampleCount = max(maximumSampleCount, 0)
        self.hardByteLimit = max(hardByteLimit, 0)
    }

    static func defaultDirectoryURL(fileManager: FileManager = .default) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("TraceHalo", isDirectory: true)
            .appendingPathComponent("History", isDirectory: true)
    }

    func load(
        retention: DashboardHistoryRetention,
        now: Date
    ) async -> DashboardHistoryLoadResult {
        guard ensureDirectoryExists() else {
            cachedSamples = []
            hasLoaded = true
            return DashboardHistoryLoadResult(samples: [])
        }

        let URLs = segmentURLs()
        var loadedSamples: [DashboardTelemetrySample] = []
        var invalidURLs: [URL] = []
        var acceptedBytes = 0

        // Read newest segments first so an unexpectedly large directory can
        // never displace the current valid history or cause unbounded startup I/O.
        for URL in URLs.reversed() {
            guard let fileSize = fileSize(at: URL), fileSize <= hardByteLimit else {
                invalidURLs.append(URL)
                continue
            }
            guard acceptedBytes <= hardByteLimit - fileSize else {
                invalidURLs.append(URL)
                continue
            }
            guard let archive = decodeArchive(at: URL) else {
                invalidURLs.append(URL)
                continue
            }
            acceptedBytes += fileSize
            loadedSamples.append(contentsOf: archive.samples)
        }

        invalidURLs.forEach(removeItemIfPresent)
        cachedSamples = constrainedSamples(
            loadedSamples,
            retention: retention,
            now: now
        )
        synchronizeAllSegments(with: cachedSamples)
        hasLoaded = true
        return DashboardHistoryLoadResult(samples: cachedSamples)
    }

    func record(
        _ sample: DashboardTelemetrySample,
        retention: DashboardHistoryRetention,
        now: Date
    ) async {
        if !hasLoaded {
            _ = await load(retention: retention, now: now)
        }

        var next = cachedSamples
        let cutoff = now.addingTimeInterval(-retention.duration)
        if sample.date >= cutoff,
           sample.date <= now,
           Self.isValid(sample) {
            let bucket = Self.minuteBucket(for: sample.date)
            next.removeAll { Self.minuteBucket(for: $0.date) == bucket }
            next.append(sample)
        }
        let constrained = constrainedSamples(next, retention: retention, now: now)
        guard constrained != cachedSamples else { return }

        let previous = cachedSamples
        cachedSamples = constrained
        synchronizeChangedSegments(from: previous, to: cachedSamples)
    }

    func updateRetention(
        _ retention: DashboardHistoryRetention,
        now: Date
    ) async -> DashboardHistoryLoadResult {
        if !hasLoaded {
            return await load(retention: retention, now: now)
        }

        let previous = cachedSamples
        cachedSamples = constrainedSamples(
            cachedSamples,
            retention: retention,
            now: now
        )
        synchronizeChangedSegments(from: previous, to: cachedSamples)
        return DashboardHistoryLoadResult(samples: cachedSamples)
    }

    private func constrainedSamples(
        _ samples: [DashboardTelemetrySample],
        retention: DashboardHistoryRetention,
        now: Date
    ) -> [DashboardTelemetrySample] {
        let cutoff = now.addingTimeInterval(-retention.duration)
        let sorted = samples
            .enumerated()
            .filter { _, sample in
                sample.date >= cutoff
                    && sample.date <= now
                    && Self.isValid(sample)
            }
            .sorted { lhs, rhs in
                if lhs.element.date == rhs.element.date {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.date < rhs.element.date
            }

        var sampleByMinute: [Int64: DashboardTelemetrySample] = [:]
        for (_, sample) in sorted {
            let bucket = Self.minuteBucket(for: sample.date)
            if let existing = sampleByMinute[bucket], existing.date > sample.date {
                continue
            }
            sampleByMinute[bucket] = sample
        }

        var constrained = sampleByMinute.values.sorted { $0.date < $1.date }
        if constrained.count > maximumSampleCount {
            constrained = Array(constrained.suffix(maximumSampleCount))
        }
        return constrainedToByteLimit(constrained)
    }

    private func constrainedToByteLimit(
        _ samples: [DashboardTelemetrySample]
    ) -> [DashboardTelemetrySample] {
        guard hardByteLimit > 0, !samples.isEmpty else { return [] }

        var grouped = Self.groupedByDay(samples)
        var orderedDays = grouped.keys.sorted()
        var sizes = encodedSizes(for: grouped)
        var totalSize = sizes.values.reduce(0, +)

        while totalSize > hardByteLimit, orderedDays.count > 1 {
            let oldestDay = orderedDays.removeFirst()
            grouped.removeValue(forKey: oldestDay)
            totalSize -= sizes.removeValue(forKey: oldestDay) ?? 0
        }

        guard totalSize > hardByteLimit,
              let remainingDay = orderedDays.first,
              let daySamples = grouped[remainingDay]
        else {
            return orderedDays.flatMap { grouped[$0] ?? [] }
        }

        let fittingSuffix = largestFittingSuffix(of: daySamples)
        return fittingSuffix
    }

    private func largestFittingSuffix(
        of samples: [DashboardTelemetrySample]
    ) -> [DashboardTelemetrySample] {
        var lowerBound = 0
        var upperBound = samples.count
        var best: [DashboardTelemetrySample] = []

        while lowerBound <= upperBound {
            let candidateCount = (lowerBound + upperBound) / 2
            let candidate = Array(samples.suffix(candidateCount))
            let size = encodedArchive(candidate)?.count ?? Int.max
            if size <= hardByteLimit {
                best = candidate
                lowerBound = candidateCount + 1
            } else {
                upperBound = candidateCount - 1
            }
        }
        return best
    }

    private func synchronizeAllSegments(
        with samples: [DashboardTelemetrySample]
    ) {
        guard ensureDirectoryExists() else { return }

        let grouped = Self.groupedByDay(samples)
        let expectedDays = Set(grouped.keys)

        for (day, daySamples) in grouped {
            guard let data = encodedArchive(daySamples) else { continue }
            try? data.write(to: segmentURL(for: day), options: .atomic)
        }

        for URL in segmentURLs() {
            guard let day = dayIndex(from: URL), expectedDays.contains(day) else {
                removeItemIfPresent(URL)
                continue
            }
        }
    }

    private func synchronizeChangedSegments(
        from previous: [DashboardTelemetrySample],
        to next: [DashboardTelemetrySample]
    ) {
        guard ensureDirectoryExists() else { return }

        let previousByDay = Self.groupedByDay(previous)
        let nextByDay = Self.groupedByDay(next)
        let changedDays = Set(previousByDay.keys).union(nextByDay.keys).filter {
            previousByDay[$0] != nextByDay[$0]
        }

        for day in changedDays {
            guard let samples = nextByDay[day], !samples.isEmpty else {
                removeItemIfPresent(segmentURL(for: day))
                continue
            }
            guard let data = encodedArchive(samples) else { continue }
            try? data.write(to: segmentURL(for: day), options: .atomic)
        }
    }

    private func encodedSizes(
        for grouped: [Int64: [DashboardTelemetrySample]]
    ) -> [Int64: Int] {
        grouped.reduce(into: [:]) { result, entry in
            result[entry.key] = encodedArchive(entry.value)?.count ?? Int.max
        }
    }

    private func encodedArchive(
        _ samples: [DashboardTelemetrySample]
    ) -> Data? {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try? encoder.encode(Archive(samples: samples))
    }

    private func decodeArchive(at URL: URL) -> Archive? {
        guard let data = try? Data(contentsOf: URL, options: .mappedIfSafe),
              let archive = try? PropertyListDecoder().decode(Archive.self, from: data),
              archive.version == Archive.currentVersion
        else {
            return nil
        }
        return archive
    }

    private func fileSize(at URL: URL) -> Int? {
        guard let values = try? URL.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize >= 0
        else {
            return nil
        }
        return fileSize
    }

    private func ensureDirectoryExists() -> Bool {
        do {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            return true
        } catch {
            return false
        }
    }

    private func segmentURLs() -> [URL] {
        let URLs = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        return URLs
            .filter {
                $0.lastPathComponent.hasPrefix(Self.filePrefix)
                    && $0.lastPathComponent.hasSuffix(Self.fileSuffix)
            }
            .sorted {
                (dayIndex(from: $0) ?? .min) < (dayIndex(from: $1) ?? .min)
            }
    }

    private func segmentURL(for day: Int64) -> URL {
        directoryURL.appendingPathComponent(
            "\(Self.filePrefix)\(day)\(Self.fileSuffix)",
            isDirectory: false
        )
    }

    private func dayIndex(from URL: URL) -> Int64? {
        let name = URL.lastPathComponent
        guard name.hasPrefix(Self.filePrefix), name.hasSuffix(Self.fileSuffix) else {
            return nil
        }
        let start = name.index(name.startIndex, offsetBy: Self.filePrefix.count)
        let end = name.index(name.endIndex, offsetBy: -Self.fileSuffix.count)
        return Int64(name[start ..< end])
    }

    private func removeItemIfPresent(_ URL: URL) {
        try? fileManager.removeItem(at: URL)
    }

    private static func minuteBucket(for date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSince1970 / persistenceSampleInterval))
    }

    private static func dayIndex(for date: Date) -> Int64 {
        Int64(floor(date.timeIntervalSince1970 / (24 * 60 * 60)))
    }

    private static func groupedByDay(
        _ samples: [DashboardTelemetrySample]
    ) -> [Int64: [DashboardTelemetrySample]] {
        Dictionary(grouping: samples, by: { dayIndex(for: $0.date) })
    }

    private static func isValid(_ sample: DashboardTelemetrySample) -> Bool {
        let requiredValues = [
            sample.cpuPercent,
            sample.memoryPressurePercent,
            sample.networkReceivedBytesPerSecond,
            sample.networkSentBytesPerSecond
        ]
        guard requiredValues.allSatisfy(\.isFinite),
              (0 ... 100).contains(sample.cpuPercent),
              (0 ... 100).contains(sample.memoryPressurePercent),
              sample.networkReceivedBytesPerSecond >= 0,
              sample.networkSentBytesPerSecond >= 0
        else {
            return false
        }

        let optionalPercentages = [sample.gpuPercent, sample.storageUsedPercent]
        guard optionalPercentages.allSatisfy({ value in
            value.map { $0.isFinite && (0 ... 100).contains($0) } ?? true
        }) else {
            return false
        }

        return sample.temperatureCelsius.map(\.isFinite) ?? true
    }
}
