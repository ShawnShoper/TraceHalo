import Foundation
import TraceHaloCore

private final class ReplyBox: @unchecked Sendable {
    let reply: (Data) -> Void

    init(_ reply: @escaping (Data) -> Void) {
        self.reply = reply
    }
}

/// Fixed-function service: callers can request one read-only snapshot. There is
/// deliberately no method that accepts arbitrary keys or changes fan state.
private final class SensorHelperService: NSObject, SensorHelperXPCProtocol, @unchecked Sendable {
    private let sampler = ReadOnlyHardwareSensorSampler()

    func fetchReadOnlySnapshot(withReply reply: @escaping (Data) -> Void) {
        let replyBox = ReplyBox(reply)
        Task { [sampler, replyBox] in
            let payload = await sampler.sample()
            do {
                replyBox.reply(try JSONEncoder().encode(payload))
            } catch {
                let fallback = SensorHelperPayload(
                    temperatures: [],
                    fans: [],
                    cpuTemperatureCelsius: nil,
                    gpuTemperatureCelsius: nil,
                    errorCode: .encodingFailed,
                    errorMessage: error.localizedDescription
                )
                replyBox.reply((try? JSONEncoder().encode(fallback)) ?? Data())
            }
        }
    }
}

private final class SensorHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        newConnection.exportedInterface = NSXPCInterface(with: SensorHelperXPCProtocol.self)
        newConnection.exportedObject = SensorHelperService()
        newConnection.resume()
        return true
    }
}

@main
private enum SensorHelperMain {
    static func main() {
        let delegate = SensorHelperListenerDelegate()
        let listener = NSXPCListener(machServiceName: SensorHelperConstants.machServiceName)
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
    }
}
