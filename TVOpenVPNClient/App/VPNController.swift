import Foundation
import NetworkExtension
import OSLog
import SwiftUI

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var status: NEVPNStatus = .invalid
    @Published var lastError: String?
    @Published var username = ""
    @Published var password = ""

    private var manager: NETunnelProviderManager?
    private let logger = Logger(subsystem: "com.yusuf.TVOpenVPNClient", category: "VPNController")

    func load() async {
        do {
            logger.info("Loading VPN manager")
            manager = try await loadOrCreateManager()
            status = manager?.connection.status ?? .invalid
            logger.info("VPN manager loaded with status: \(self.status.displayName, privacy: .public)")
            NotificationCenter.default.addObserver(
                forName: .NEVPNStatusDidChange,
                object: manager?.connection,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.status = self?.manager?.connection.status ?? .invalid
                    if let status = self?.status {
                        self?.logger.info("VPN status changed: \(status.displayName, privacy: .public)")
                    }
                }
            }
        } catch {
            logger.error("Failed to load VPN manager: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func connect(profile: OpenVPNProfile) async {
        do {
            logger.info("Connect requested for profile: \(profile.name, privacy: .public), remote: \(profile.summary.remoteHost, privacy: .public):\(profile.summary.remotePort)")
            let manager = try await loadOrCreateManager()
            try await configure(manager: manager, profile: profile)
            logger.info("Starting VPN tunnel. Username supplied: \(!self.username.isEmpty), password supplied: \(!self.password.isEmpty)")
            try manager.connection.startVPNTunnel(options: [:])
            status = manager.connection.status
            logger.info("startVPNTunnel returned. Current status: \(self.status.displayName, privacy: .public)")
            lastError = nil
        } catch {
            logger.error("Failed to start VPN tunnel: \(error.localizedDescription, privacy: .public)")
            lastError = error.localizedDescription
        }
    }

    func disconnect() {
        logger.info("Disconnect requested")
        manager?.connection.stopVPNTunnel()
        status = manager?.connection.status ?? .invalid
        logger.info("stopVPNTunnel returned. Current status: \(self.status.displayName, privacy: .public)")
    }

    private func configure(manager: NETunnelProviderManager, profile: OpenVPNProfile) async throws {
        let partoutProfile = try PartoutIntegration.makeProfile(
            from: profile,
            username: username,
            password: password
        )
        let tunnelProtocol = try PartoutIntegration.protocolCoder.protocolConfiguration(
            from: partoutProfile,
            title: { _ in AppConstants.vpnDescription }
        )
        tunnelProtocol.serverAddress = "\(profile.summary.remoteHost):\(profile.summary.remotePort)"

        manager.localizedDescription = AppConstants.vpnDescription
        manager.protocolConfiguration = tunnelProtocol
        manager.isEnabled = true
        logger.info("Saving VPN preferences for provider: \(AppConstants.providerBundleIdentifier, privacy: .public)")
        try await manager.saveToPreferences()
        try await manager.loadFromPreferences()
        logger.info("VPN preferences saved and reloaded")
        self.manager = manager
    }

    private func loadOrCreateManager() async throws -> NETunnelProviderManager {
        if let manager {
            logger.info("Using cached VPN manager")
            return manager
        }

        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        logger.info("Loaded \(managers.count) VPN manager(s) from preferences")
        if let existing = managers.first(where: { $0.localizedDescription == AppConstants.vpnDescription }) {
            logger.info("Using existing VPN manager")
            manager = existing
            return existing
        }

        logger.info("Creating new VPN manager")
        let created = NETunnelProviderManager()
        manager = created
        return created
    }
}

extension NEVPNStatus {
    var displayName: String {
        switch self {
        case .invalid: "Not configured"
        case .disconnected: "Disconnected"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .reasserting: "Reconnecting"
        case .disconnecting: "Disconnecting"
        @unknown default: "Unknown"
        }
    }
}
