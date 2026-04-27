import Foundation
@preconcurrency import NetworkExtension
import Partout

final class PacketTunnelProvider: NEPacketTunnelProvider, @unchecked Sendable {
    private var forwarder: NEPTPForwarder?

    override func startTunnel(options: [String: NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        let completion = ErrorCompletion(completionHandler)
        Task {
            do {
                try await startPartoutTunnel()
                completion.call(nil)
            } catch {
                completion.call(error)
            }
        }
    }

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        let completion = VoidCompletion(completionHandler)
        Task {
            await forwarder?.stopTunnel(with: reason)
            forwarder = nil
            PartoutLogger.default.flushLog()
            completion.call()
        }
    }

    override func cancelTunnelWithError(_ error: Error?) {
        PartoutLogger.default.flushLog()
        super.cancelTunnelWithError(error)
    }

    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        let completion = DataCompletion(completionHandler)
        Task {
            let response = await forwarder?.handleAppMessage(messageData)
            completion.call(response)
        }
    }

    override func wake() {
        forwarder?.wake()
    }

    override func sleep(completionHandler: @escaping () -> Void) {
        let completion = VoidCompletion(completionHandler)
        Task {
            await forwarder?.sleep()
            completion.call()
        }
    }

    private func startPartoutTunnel() async throws {
        do {
            configurePartoutLogging()

            let profile = try Profile(withNEProvider: self, decoder: .tvOpenVPNClient)
            let context = PartoutLoggerContext(profile.id)
            let controller = NETunnelController(
                provider: self,
                profile: profile,
                options: .init()
            )

            forwarder = try NEPTPForwarder(
                context,
                profile: profile,
                connectionFactory: Registry.tvOpenVPNClient,
                controller: controller,
                environment: PartoutIntegration.tunnelEnvironment
            )

            pp_log(context, .os, .notice, "Starting Partout packet tunnel")
            try await forwarder?.startTunnel(options: nil)
        } catch {
            PartoutLogger.default.flushLog()
            throw error
        }
    }

    private func configurePartoutLogging() {
        var loggerBuilder = PartoutLogger.Builder()
        loggerBuilder.setDestination(OSLogDestination(.core), for: [.core])
        loggerBuilder.setDestination(OSLogDestination(.os), for: [.os])
        loggerBuilder.setDestination(OSLogDestination(.openvpn), for: [.openvpn])
        loggerBuilder.logsModules = true
        PartoutLogger.register(loggerBuilder.build())
    }
}

private final class ErrorCompletion: @unchecked Sendable {
    private let handler: (Error?) -> Void

    init(_ handler: @escaping (Error?) -> Void) {
        self.handler = handler
    }

    func call(_ error: Error?) {
        handler(error)
    }
}

private final class VoidCompletion: @unchecked Sendable {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    func call() {
        handler()
    }
}

private final class DataCompletion: @unchecked Sendable {
    private let handler: ((Data?) -> Void)?

    init(_ handler: ((Data?) -> Void)?) {
        self.handler = handler
    }

    func call(_ data: Data?) {
        handler?(data)
    }
}
