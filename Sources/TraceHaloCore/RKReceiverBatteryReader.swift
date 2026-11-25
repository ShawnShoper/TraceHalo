import CryptoKit
import Foundation
import IOKit
import IOKit.hid
import IOKit.hidsystem

/// Opt-in reader for the verified R87PRO receiver. Call away from the main thread.
/// Only fixed identification/status/battery queries are sent; keyboard reports
/// are never subscribed to or read. A driver timestamp proves new delivery, not
/// when the keyboard sampled its battery.
public enum RKReceiverBatteryReader {
    private static let flight = Flight()
    // This exact descriptor contains one FF02:0002 report-13 input/output pair,
    // each 19 payload bytes, and one FF04:0002 marker. Firmware changes fail closed.
    private static let descriptorSHA256 =
        "a44371659f2cd4a29ea85fcf673e9251dc06d1b004f0552354d13d6323ea722e"
    private static let timeout: TimeInterval = 4.5

    public static func read(locationID: UInt64) -> RKReceiverBatteryResult {
        guard RuntimeSafetyMode.current == .live, locationID != 0 else { return .unavailable }
        guard IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted else {
            return .permissionRequired
        }
        guard flight.begin() else { return .unavailable }
        let operation = Operation()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        DispatchQueue.global(qos: .utility).async {
            defer { flight.finish() }
            operation.complete(performRead(locationID: locationID, deadline: deadline))
        }
        // SetReport has no dependable cancellation on every macOS HID driver.
        // A stuck worker owns its handle/buffer until it returns, and blocks new
        // workers. Never exit the app or free an in-flight report on a timeout.
        guard operation.finished.wait(timeout: .now() + timeout) == .success else {
            return .unavailable
        }
        return operation.result()
    }

    private static func performRead(locationID: UInt64, deadline: TimeInterval) -> RKReceiverBatteryResult {
        guard RuntimeSafetyMode.current == .live,
              ProcessInfo.processInfo.systemUptime < deadline,
              let candidate = receiver(locationID: locationID),
              let before = vendorInput(candidate) else { return .unavailable }
        guard IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess else {
            return .unavailable
        }
        defer { IOHIDDeviceClose(candidate, IOOptionBits(kIOHIDOptionsTypeNone)) }
        guard let element = vendorInput(candidate),
              IOHIDElementGetCookie(element) == IOHIDElementGetCookie(before) else {
            return .unavailable
        }
        // macOS keeps the old timestamp when an identical report repeats. The
        // descriptor-proven receiver's generic 07 read changes the cached frame
        // before 05. Neither that status nor an old identity establishes a model.
        let initialStatus = exchange(0x07, minimumLength: 1, device: candidate,
                                     element: element, deadline: deadline)
        switch initialStatus {
        case .invalid, .unavailable: return .unavailable
        case .reply, .noReply: break
        }
        guard case let .reply(identity) = exchange(0x05, minimumLength: 6, device: candidate,
                                                  element: element, deadline: deadline) else {
            return .unavailable
        }
        guard RKReceiverBatteryProtocol.isR87Pro(identity) else { return .otherKeyboard }
        let status: [UInt8]
        if case let .reply(online) = initialStatus {
            status = online
        } else {
            // The previous call may have stopped at 07. A fresh 05 has now
            // changed the frame, so another 07 can prove current link status.
            guard case let .reply(online) = exchange(0x07, minimumLength: 1, device: candidate,
                                                    element: element, deadline: deadline) else {
                return .unavailable
            }
            status = online
        }
        guard status[0] > 0 else { return .offline }
        switch exchange(0x4a, minimumLength: 2, device: candidate, element: element, deadline: deadline) {
        case let .reply(battery):
            return RKReceiverBatteryProtocol.reading(battery) ?? .unavailable
        case .noReply:
            return .noBatteryReport
        case .invalid, .unavailable:
            return .unavailable
        }
    }

    private enum Exchange {
        case reply([UInt8]), noReply, invalid, unavailable
    }

    private static func exchange(
        _ command: UInt8, minimumLength: Int, device: IOHIDDevice,
        element: IOHIDElement, deadline: TimeInterval
    ) -> Exchange {
        guard let request = RKReceiverBatteryProtocol.request(command),
              RuntimeSafetyMode.current == .live,
              ProcessInfo.processInfo.systemUptime < deadline else { return .unavailable }
        let initial = cachedValue(device, element)
        guard initial.status == kIOReturnSuccess else { return .unavailable }
        let previousTimestamp = initial.value.map(IOHIDValueGetTimeStamp) ?? 0
        let queryStarted = mach_absolute_time()
        guard ProcessInfo.processInfo.systemUptime < deadline else { return .unavailable }
        let sent = request.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0x13, $0.baseAddress!, $0.count)
        }
        // A stalled write may resume after the caller timed out. Do not issue
        // another command, accept its value or extend the original deadline.
        guard sent == kIOReturnSuccess, ProcessInfo.processInfo.systemUptime < deadline else {
            return .unavailable
        }
        let responseDeadline = min(deadline, ProcessInfo.processInfo.systemUptime + 0.9)
        var lastTimestamp = previousTimestamp
        var invalidReply = false
        while ProcessInfo.processInfo.systemUptime < responseDeadline {
            let cached = cachedValue(device, element)
            guard cached.status == kIOReturnSuccess else { return .unavailable }
            if let value = cached.value {
                let returned = IOHIDValueGetElement(value)
                guard IOHIDElementGetCookie(returned) == IOHIDElementGetCookie(element),
                      IOHIDElementGetReportID(returned) == 0x13 else { return .invalid }
                let timestamp = IOHIDValueGetTimeStamp(value)
                if timestamp > lastTimestamp, timestamp >= queryStarted, timestamp <= mach_absolute_time() {
                    lastTimestamp = timestamp
                    guard IOHIDValueGetLength(value) == 19 else { return .invalid }
                    let frame = [UInt8(0x13)] + Array(UnsafeBufferPointer(
                        start: IOHIDValueGetBytePtr(value), count: 19
                    ))
                    // Other vendor replies/notifications and request echoes do
                    // not satisfy this query. Nothing from them is retained.
                    if frame != request, frame[1] == command {
                        if let payload = RKReceiverBatteryProtocol.payload(
                            frame, command: command, minimumLength: minimumLength
                        ) {
                            guard ProcessInfo.processInfo.systemUptime < responseDeadline else {
                                return .noReply
                            }
                            return .reply(payload)
                        }
                        invalidReply = true
                    }
                }
            }
            Thread.sleep(forTimeInterval: min(0.01, max(0, responseDeadline - ProcessInfo.processInfo.systemUptime)))
        }
        return invalidReply ? .invalid : .noReply
    }

    private static func cachedValue(_ device: IOHIDDevice, _ element: IOHIDElement)
        -> (status: IOReturn, value: IOHIDValue?) {
        var unmanaged: Unmanaged<IOHIDValue>?
        let result = withUnsafeMutablePointer(to: &unmanaged) {
            IOHIDDeviceGetValueWithOptions(device, element,
                UnsafeMutableRawPointer($0).assumingMemoryBound(to: Unmanaged<IOHIDValue>.self),
                0x00040000) // kIOHIDDeviceGetValueWithoutUpdate: no GET_REPORT.
        }
        return (result, result == kIOReturnSuccess ? unmanaged?.takeUnretainedValue() : nil)
    }

    private static func receiver(locationID: UInt64) -> IOHIDDevice? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDDevice"),
                                          &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var parents = Set<UInt64>()
        var candidates: [IOHIDDevice] = []
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            guard number(service, "VendorID") == 0x3554,
                  number(service, "ProductID") == 0xfa09,
                  number(service, "LocationID") == locationID else { continue }
            guard property(service, "Transport") as? String == "USB",
                  property(service, "Product") as? String == "2.4G Wireless Receiver",
                  property(service, "Manufacturer") as? String == "Compx",
                  let parent = physicalUSB(service) else { return nil }
            parents.insert(parent)
            guard let descriptor = property(service, kIOHIDReportDescriptorKey) as? Data else { return nil }
            let digest = SHA256.hash(data: descriptor).map { String(format: "%02x", $0) }.joined()
            if digest == descriptorSHA256 {
                guard let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { return nil }
                candidates.append(device)
            }
        }
        guard parents.count == 1, candidates.count == 1 else { return nil }
        return candidates[0]
    }

    private static func vendorInput(_ device: IOHIDDevice) -> IOHIDElement? {
        let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] ?? []
        guard elements.filter({
            IOHIDElementGetType($0) == kIOHIDElementTypeCollection &&
            IOHIDElementGetUsagePage($0) == 0xff04 && IOHIDElementGetUsage($0) == 2
        }).count == 1 else { return nil }
        let inputs = elements.filter { element in
            let type = IOHIDElementGetType(element).rawValue
            guard (1...4).contains(type), IOHIDElementGetReportID(element) == 0x13,
                  IOHIDElementGetUsagePage(element) == 0xff02 else { return false }
            let size = UInt64(IOHIDElementGetReportSize(element))
            let bits = IOHIDElementIsArray(element) ? size * UInt64(IOHIDElementGetReportCount(element)) : size
            guard bits == 152 else { return false }
            var ancestor = IOHIDElementGetParent(element)
            for _ in 0..<32 {
                guard let parent = ancestor else { return false }
                if IOHIDElementGetType(parent) == kIOHIDElementTypeCollection,
                   IOHIDElementGetUsagePage(parent) == 0xff02, IOHIDElementGetUsage(parent) == 2 { return true }
                ancestor = IOHIDElementGetParent(parent)
            }
            return false
        }
        return inputs.count == 1 ? inputs[0] : nil
    }

    private static func property(_ service: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func number(_ service: io_registry_entry_t, _ key: String) -> UInt64? {
        (property(service, key) as? NSNumber)?.uint64Value
    }

    private static func physicalUSB(_ service: io_registry_entry_t) -> UInt64? {
        var current = service
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<32 {
            if IOObjectConformsTo(current, "IOUSBHostDevice") != 0 || IOObjectConformsTo(current, "IOUSBDevice") != 0 {
                var identifier: UInt64 = 0
                return IORegistryEntryGetRegistryEntryID(current, &identifier) == KERN_SUCCESS ? identifier : nil
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            IOObjectRelease(current)
            current = parent
        }
        return nil
    }

    private final class Flight: @unchecked Sendable {
        private let lock = NSLock()
        private var active = false
        func begin() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard !active else { return false }
            active = true
            return true
        }
        func finish() { lock.lock(); active = false; lock.unlock() }
    }

    private final class Operation: @unchecked Sendable {
        let finished = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var value: RKReceiverBatteryResult = .unavailable
        func complete(_ result: RKReceiverBatteryResult) {
            lock.lock(); value = result; lock.unlock()
            finished.signal()
        }
        func result() -> RKReceiverBatteryResult {
            lock.lock(); defer { lock.unlock() }
            return value
        }
    }
}
