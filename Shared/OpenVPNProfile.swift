import Foundation

struct OpenVPNProfile: Identifiable, Codable, Equatable {
    enum Source: String, Codable {
        case bundled
        case sharedContainer
    }

    let id: UUID
    var name: String
    var fileName: String
    var source: Source
    var ovpn: String
    var summary: OpenVPNProfileSummary

    init(name: String, fileName: String, source: Source, ovpn: String) throws {
        self.id = UUID()
        self.name = name
        self.fileName = fileName
        self.source = source
        self.ovpn = ovpn
        self.summary = try OVPNParser.parse(ovpn, profileName: name)
    }
}

struct OpenVPNProfileSummary: Codable, Equatable {
    var profileName: String
    var remoteHost: String
    var remotePort: Int
    var proto: String
    var requiresCredentials: Bool
    var dnsServers: [String]
    var routeCount: Int
    var redirectsGateway: Bool
    var hasInlineCA: Bool
    var hasInlineCertificate: Bool
    var hasInlinePrivateKey: Bool
}

