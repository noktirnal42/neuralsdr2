import Foundation
import Network

public final class Dump978RawClient {
    public enum State: Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)
    }

    public var onStateChanged: ((State) -> Void)?
    public var onMessage: ((String) -> Void)?

    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.neuralsdr2.dump978.raw")
    private var buffer = Data()

    public init() {}

    public func connect(host: String, port: UInt16) {
        disconnect()

        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            onStateChanged?(.failed("Invalid dump978 port"))
            return
        }

        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        self.connection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .setup, .waiting:
                self?.onStateChanged?(.connecting)
            case .ready:
                self?.onStateChanged?(.connected)
                self?.receiveNextChunk()
            case .failed(let error):
                self?.onStateChanged?(.failed(error.localizedDescription))
            case .cancelled:
                self?.onStateChanged?(.disconnected)
            default:
                break
            }
        }

        onStateChanged?(.connecting)
        connection.start(queue: queue)
    }

    public func disconnect() {
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: false)
        onStateChanged?(.disconnected)
    }

    private func receiveNextChunk() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.emitBufferedLines()
            }

            if let error {
                self.onStateChanged?(.failed(error.localizedDescription))
                return
            }

            if isComplete {
                self.onStateChanged?(.disconnected)
                return
            }

            self.receiveNextChunk()
        }
    }

    private func emitBufferedLines() {
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.prefix(upTo: newline)
            buffer.removeSubrange(...newline)

            guard var line = String(data: lineData, encoding: .utf8) else { continue }
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            onMessage?(line)
        }
    }
}
