import Darwin
import Foundation

/// Reads a read-only command without blocking on a full stdout pipe or an
/// unresponsive child. The caller owns the Process; only that child is stopped.
enum ProcessOutputReader {
    enum Failure: Error, Equatable {
        case timedOut
        case outputTooLarge
        case unsuccessfulExit(Int32)
        case readFailed(Int32)
    }

    static func read(
        from process: Process,
        timeout: TimeInterval = 3,
        maximumOutputBytes: Int = 1_048_576,
        isCancelled: () -> Bool = { Task.isCancelled }
    ) throws -> Data {
        guard !isCancelled() else { throw CancellationError() }
        guard timeout.isFinite, timeout > 0 else { throw Failure.timedOut }
        guard maximumOutputBytes > 0 else { throw Failure.outputTooLarge }

        let output = Pipe()
        let descriptor = output.fileHandleForReading.fileDescriptor
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw Failure.readFailed(errno)
        }
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        try process.run()
        // Foundation has duplicated this descriptor into the child. Closing
        // our writer allows read() to see EOF when the child closes stdout.
        try? output.fileHandleForWriting.close()
        defer { stopIfRunning(process) }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            guard !isCancelled() else { throw CancellationError() }
            guard clock.now < deadline else { throw Failure.timedOut }

            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard count <= maximumOutputBytes - data.count else { throw Failure.outputTooLarge }
                data.append(contentsOf: buffer.prefix(count))
                continue
            }
            if count == 0, !process.isRunning {
                guard process.terminationStatus == 0 else {
                    throw Failure.unsuccessfulExit(process.terminationStatus)
                }
                return data
            }
            if count < 0 {
                let readError = errno
                guard readError == EAGAIN || readError == EINTR else {
                    throw Failure.readFailed(readError)
                }
            }
            // EOF alone is not success: a child can close stdout and then
            // hang. Both process termination and stdout EOF must be observed.
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    private static func stopIfRunning(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let clock = ContinuousClock()
        let gracefulDeadline = clock.now.advanced(by: .milliseconds(100))
        while process.isRunning, clock.now < gracefulDeadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
        if process.isRunning {
            // A command ignoring SIGTERM must not keep a storage probe alive.
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
        }
        let cleanupDeadline = clock.now.advanced(by: .milliseconds(250))
        while process.isRunning, clock.now < cleanupDeadline {
            Thread.sleep(forTimeInterval: 0.005)
        }
    }
}
