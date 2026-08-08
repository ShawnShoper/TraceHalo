import Foundation
import Testing
@testable import SystemScopeCore

@Suite("GPU registry statistics")
struct GPUStatisticsReaderTests {
    @Test("decodes utilization and memory without touching hardware")
    func decodesPerformanceDictionary() {
        let sample = GPUStatisticsReader.sample(from: [
            "Device Utilization %": NSNumber(value: 37),
            "In use system memory": NSNumber(value: 1_536_000_000),
            "Alloc system memory": NSNumber(value: 8_192_000_000)
        ])

        #expect(sample?.utilizationPercent == 37)
        #expect(sample?.usedMemoryBytes == 1_536_000_000)
        #expect(sample?.allocatedMemoryBytes == 8_192_000_000)
    }

    @Test("clamps invalid utilization and preserves unavailable state")
    func clampsAndRejectsEmptyInput() {
        #expect(GPUStatisticsReader.sample(from: ["Device Utilization %": 140])?.utilizationPercent == 100)
        #expect(GPUStatisticsReader.sample(from: ["Renderer Utilization %": -20])?.utilizationPercent == 0)
        #expect(GPUStatisticsReader.sample(from: [:]) == nil)
    }

    @Test("attributes each sample to the matching GPU registry ID")
    func matchesRegistryIDsWithoutCrossDeviceFallback() {
        let first = GPUPerformanceSample(utilizationPercent: 12, usedMemoryBytes: 100, allocatedMemoryBytes: 200)
        let second = GPUPerformanceSample(utilizationPercent: 74, usedMemoryBytes: 700, allocatedMemoryBytes: 900)
        let readings = [
            GPUPerformanceReading(registryID: 11, sample: first),
            GPUPerformanceReading(registryID: 22, sample: second)
        ]

        #expect(GPUStatisticsReader.sample(for: 11, in: readings, totalGPUCount: 2) == first)
        #expect(GPUStatisticsReader.sample(for: 22, in: readings, totalGPUCount: 2) == second)
        #expect(GPUStatisticsReader.sample(for: 33, in: readings, totalGPUCount: 2) == nil)
    }

    @Test("allows an unambiguous single-GPU registry fallback")
    func fallsBackOnlyForSingleGPU() {
        let sample = GPUPerformanceSample(utilizationPercent: 41, usedMemoryBytes: nil, allocatedMemoryBytes: nil)
        let readings = [GPUPerformanceReading(registryID: 99, sample: sample)]

        #expect(GPUStatisticsReader.sample(for: 11, in: readings, totalGPUCount: 1) == sample)
        #expect(GPUStatisticsReader.sample(for: 11, in: readings, totalGPUCount: 2) == nil)
    }
}
