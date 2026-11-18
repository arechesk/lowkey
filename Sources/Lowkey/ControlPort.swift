import AppKit
import LowkeyCore

// CFMessagePort requires a synchronous reply. Only the serial IPC queue waits;
// WebKit and the controller stay on the main actor, which must be free to receive replies.
private func answerControlRequest(_ port: CFMessagePort?, _ id: Int32, _ data: CFData?,
                                  _ info: UnsafeMutableRawPointer?) -> Unmanaged<CFData>? {
    guard let info, let data, let request = ControlRequest(payload: data as Data) else {
        return .passRetained(Data("invalid".utf8) as CFData)
    }
    let controller = Unmanaged<AppController>.fromOpaque(info).takeUnretainedValue()
    let done = DispatchSemaphore(value: 0)
    let deadline = DispatchTime.now() + .seconds(4)
    var reply = "result unknown"
    Task { @MainActor in
        if DispatchTime.now() < deadline { reply = await controller.handle(request) }
        done.signal()
    }
    let result = done.wait(timeout: deadline) == .success ? reply : "result unknown"
    return .passRetained(Data(result.utf8) as CFData)
}

@MainActor final class ControlPort {
    private let port: CFMessagePort

    init?(controller: AppController) {
        var context = CFMessagePortContext(version: 0, info: Unmanaged.passUnretained(controller).toOpaque(),
                                           retain: { p in _ = Unmanaged<AppController>.fromOpaque(p!).retain(); return p },
                                           release: { p in Unmanaged<AppController>.fromOpaque(p!).release() }, copyDescription: nil)
        let name = ControlRequest.portName(pid: getpid()) as CFString
        guard let port = CFMessagePortCreateLocal(nil, name, answerControlRequest, &context, nil) else { return nil }
        self.port = port
        CFMessagePortSetDispatchQueue(port, DispatchQueue(label: "io.bobuk.lowkey.control"))
    }

    deinit { CFMessagePortInvalidate(port) }
}
