import Foundation
import Partout

enum PartoutIntegration {
    static let profileID = UUID(uuidString: "B316870C-4970-4981-8CE7-95700B2C33EC")!

    static var protocolCoder: ProviderNEProtocolCoder {
        ProviderNEProtocolCoder(
            .global,
            tunnelBundleIdentifier: AppConstants.providerBundleIdentifier,
            coder: CodingRegistry(registry: .tvOpenVPNClient, withLegacyEncoding: { false })
        )
    }

    static var tunnelEnvironment: UserDefaultsEnvironment {
        guard let defaults = UserDefaults(suiteName: AppConstants.appGroupIdentifier) else {
            fatalError("Not entitled to App Group: \(AppConstants.appGroupIdentifier)")
        }
        return UserDefaultsEnvironment(profileId: nil, defaults: defaults)
    }

    static func makeProfile(from profile: OpenVPNProfile, username: String, password: String) throws -> Profile {
        let parser = StandardOpenVPNParser(decrypter: nil)
        let result = try parser.parsed(fromContents: profile.ovpn)

        var moduleBuilder = OpenVPNModule.Builder(configurationBuilder: result.configuration.builder())
        if !username.isEmpty || !password.isEmpty {
            moduleBuilder.credentials = OpenVPN.Credentials.Builder(
                username: username,
                password: password
            ).build()
        } else {
            moduleBuilder.credentials = result.credentials
        }

        let openVPNModule = try moduleBuilder.build()
        var profileBuilder = Profile.Builder(id: profileID)
        profileBuilder.name = profile.name
        profileBuilder.modules = [openVPNModule]
        profileBuilder.activeModulesIds = [openVPNModule.id]

        return try profileBuilder.build()
    }

    static func moduleURL(for name: String) -> URL {
        do {
            let url = cachesURL.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            fatalError("No access to Partout module cache: \(error)")
        }
    }

    private static var cachesURL: URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppConstants.appGroupIdentifier) {
            return groupURL.appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Caches", isDirectory: true)
        }

        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TVOpenVPNClient", isDirectory: true)
            .appendingPathComponent("Partout", isDirectory: true)
    }
}

extension Registry {
    static let tvOpenVPNClient = Registry(
        withKnown: true,
        allImplementations: [
            OpenVPNModule.Implementation(
                importerBlock: {
                    StandardOpenVPNParser(decrypter: nil)
                },
                connectionBlock: { parameters, module in
                    let context = PartoutLoggerContext(parameters.profile.id)
                    return try OpenVPNConnection(
                        context,
                        parameters: parameters,
                        module: module,
                        cachesURL: PartoutIntegration.moduleURL(for: "OpenVPN")
                    )
                }
            )
        ]
    )
}

extension NEProtocolDecoder where Self == ProviderNEProtocolCoder {
    static var tvOpenVPNClient: Self {
        PartoutIntegration.protocolCoder
    }
}
