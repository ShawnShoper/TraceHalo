import Foundation

/// The capacity and health subset of an IOPowerSources/AppleSmartBattery sample.
/// Keeping the parser independent from IOKit makes the unit and precedence rules
/// deterministic and testable without touching live hardware.
struct ParsedBatteryTelemetry: Equatable {
    var chargePercent: Double?
    var health: BatteryHealth
    var healthBasis: BatteryHealthBasis
    var currentCapacityMAh: Int?
    var maximumCapacityMAh: Int?
    var designCapacityMAh: Int?
}

enum BatteryTelemetryParser {
    static func parse(
        powerSource: [String: Any],
        registry: [String: Any]
    ) -> ParsedBatteryTelemetry {
        let sourceCurrent = integer(powerSource["Current Capacity"])
        let sourceMaximum = integer(powerSource["Max Capacity"])
        let registryCurrent = integer(registry["CurrentCapacity"])
        let registryMaximum = integer(registry["MaxCapacity"])

        // Apple power sources publish Current/Max Capacity as a normalized pair
        // (normally 0...100). They must never be labelled as mAh.
        let chargePercent = percentage(current: sourceCurrent, maximum: sourceMaximum)
            ?? percentage(current: registryCurrent, maximum: registryMaximum)

        // Only explicitly raw capacity keys are treated as mAh. In particular,
        // CurrentCapacity=48 and MaxCapacity=100 mean 48%, not 48/100 mAh.
        let rawMaximum = positiveInteger(registry["AppleRawMaxCapacity"])
        let rawCurrentCandidate = nonnegativeInteger(registry["AppleRawCurrentCapacity"])
        let rawCurrent = rawCurrentCandidate.flatMap { current -> Int? in
            guard let rawMaximum else { return current }
            return current <= rawMaximum + max(rawMaximum / 4, 100) ? current : nil
        }
        let rawDesignCandidate = positiveInteger(registry["DesignCapacity"])
        let rawDesign = capacityPairIsPlausible(rawMaximum, rawDesignCandidate)
            ? rawDesignCandidate
            : nil
        let rawChargePercent = percentage(current: rawCurrent, maximum: rawMaximum)

        let publicHealth = string(powerSource["BatteryHealth"])
            ?? string(registry["BatteryHealth"])
        let publicCondition = string(powerSource["BatteryHealthCondition"])
            ?? string(registry["BatteryHealthCondition"])
        let failureModesValue = powerSource.keys.contains("BatteryFailureModes")
            ? powerSource["BatteryFailureModes"]
            : registry["BatteryFailureModes"]
        let failureModes = failureModes(from: failureModesValue)

        let assessment = healthAssessment(
            publicHealth: publicHealth,
            publicCondition: publicCondition,
            failureModes: failureModes,
            maximumCapacityMAh: rawMaximum,
            designCapacityMAh: rawDesign
        )

        return ParsedBatteryTelemetry(
            chargePercent: chargePercent ?? rawChargePercent,
            health: assessment.health,
            healthBasis: assessment.basis,
            currentCapacityMAh: rawCurrent,
            maximumCapacityMAh: rawMaximum,
            designCapacityMAh: rawDesign
        )
    }

    private static func healthAssessment(
        publicHealth: String?,
        publicCondition: String?,
        failureModes: [String],
        maximumCapacityMAh: Int?,
        designCapacityMAh: Int?
    ) -> (health: BatteryHealth, basis: BatteryHealthBasis) {
        // A public failure condition or mode is actionable even if the broad
        // health field has not caught up yet.
        if !failureModes.isEmpty || isServiceCondition(publicCondition) {
            return (.serviceRecommended, .systemReported)
        }

        if let publicHealth {
            switch normalized(publicHealth) {
            case "good", "normal":
                return (.good, .systemReported)
            case "fair":
                return (.aging, .systemReported)
            case "poor":
                return (.serviceRecommended, .systemReported)
            default:
                break
            }
        }

        if let publicCondition, normalized(publicCondition) == "normal" {
            return (.good, .systemReported)
        }

        let estimated = BatteryHealthRules.evaluate(
            maximumCapacity: maximumCapacityMAh,
            designCapacity: designCapacityMAh,
            serviceRecommended: false
        )
        switch estimated {
        case .unknown:
            return (.unknown, .unavailable)
        case .serviceRecommended:
            // A private capacity ratio alone is not an Apple service verdict.
            return (.aging, .rawCapacityEstimate)
        case .excellent, .good, .aging:
            return (estimated, .rawCapacityEstimate)
        }
    }

    private static func isServiceCondition(_ value: String?) -> Bool {
        guard let value else { return false }
        return switch normalized(value) {
        case "check battery", "permanent battery failure", "service recommended",
             "replace soon", "replace now": true
        default: false
        }
    }

    private static func failureModes(from value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.compactMap(nonemptyString)
        }
        if let values = value as? [Any] {
            return values.compactMap { string($0) }
        }
        if let values = value as? [String: Any] {
            return values.isEmpty ? [] : values.keys.sorted()
        }
        if let value = string(value) {
            return [value]
        }
        return []
    }

    private static func capacityPairIsPlausible(_ lhs: Int?, _ rhs: Int?) -> Bool {
        guard let lhs, let rhs, lhs > 100, rhs > 100 else { return false }
        let ratio = Double(lhs) / Double(rhs)
        return (0.1...1.5).contains(ratio)
    }

    private static func percentage(current: Int?, maximum: Int?) -> Double? {
        guard let current, let maximum, current >= 0, maximum > 0 else { return nil }
        return min(max(Double(current) / Double(maximum) * 100, 0), 100)
    }

    private static func positiveInteger(_ value: Any?) -> Int? {
        guard let value = integer(value), value > 0 else { return nil }
        return value
    }

    private static func nonnegativeInteger(_ value: Any?) -> Int? {
        guard let value = integer(value), value >= 0 else { return nil }
        return value
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Int { return value }
        if let value = value as? Int64,
           value >= Int64(Int.min), value <= Int64(Int.max) {
            return Int(value)
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        return nonemptyString(value)
    }

    private static func nonemptyString(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
