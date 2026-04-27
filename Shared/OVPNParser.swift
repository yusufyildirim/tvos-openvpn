import Foundation

enum OVPNParserError: LocalizedError {
    case missingRemote
    case invalidRemote(String)

    var errorDescription: String? {
        switch self {
        case .missingRemote:
            return "The profile does not contain a remote server."
        case .invalidRemote(let line):
            return "The remote directive is invalid: \(line)"
        }
    }
}

enum OVPNParser {
    static func parse(_ text: String, profileName: String) throws -> OpenVPNProfileSummary {
        let lines = normalizedLines(from: text)
        var proto = "udp"
        var remote: (host: String, port: Int, proto: String?)?
        var requiresCredentials = false
        var dnsServers: [String] = []
        var routeCount = 0
        var redirectsGateway = false
        var inlineTags = Set<String>()

        for line in lines {
            if line.hasPrefix("<"), line.hasSuffix(">") {
                let tag = line.trimmingCharacters(in: CharacterSet(charactersIn: "<>")).lowercased()
                inlineTags.insert(tag)
                continue
            }

            let parts = splitDirective(line)
            guard let directive = parts.first?.lowercased() else { continue }

            switch directive {
            case "proto" where parts.count >= 2:
                proto = parts[1].lowercased()
            case "remote":
                guard parts.count >= 2 else { throw OVPNParserError.invalidRemote(line) }
                let port = parts.count >= 3 ? Int(parts[2]) : nil
                let remoteProto = parts.count >= 4 ? parts[3].lowercased() : nil
                remote = (parts[1], port ?? defaultPort(for: remoteProto ?? proto), remoteProto)
            case "auth-user-pass":
                requiresCredentials = true
            case "dhcp-option" where parts.count >= 3 && parts[1].caseInsensitiveCompare("DNS") == .orderedSame:
                dnsServers.append(parts[2])
            case "route":
                routeCount += 1
            case "redirect-gateway":
                redirectsGateway = true
            default:
                continue
            }
        }

        guard let remote else { throw OVPNParserError.missingRemote }

        return OpenVPNProfileSummary(
            profileName: profileName,
            remoteHost: remote.host,
            remotePort: remote.port,
            proto: remote.proto ?? proto,
            requiresCredentials: requiresCredentials,
            dnsServers: dnsServers,
            routeCount: routeCount,
            redirectsGateway: redirectsGateway,
            hasInlineCA: inlineTags.contains("ca"),
            hasInlineCertificate: inlineTags.contains("cert"),
            hasInlinePrivateKey: inlineTags.contains("key")
        )
    }

    private static func normalizedLines(from text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                    return nil
                }
                return stripTrailingComment(from: line)
            }
    }

    private static func stripTrailingComment(from line: String) -> String {
        var inQuote = false
        var output = ""

        for character in line {
            if character == "\"" {
                inQuote.toggle()
            }
            if !inQuote && (character == "#" || character == ";") {
                break
            }
            output.append(character)
        }

        return output.trimmingCharacters(in: .whitespaces)
    }

    private static func splitDirective(_ line: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuote = false

        for character in line {
            if character == "\"" {
                inQuote.toggle()
                continue
            }
            if character.isWhitespace && !inQuote {
                if !current.isEmpty {
                    parts.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }

        if !current.isEmpty {
            parts.append(current)
        }

        return parts
    }

    private static func defaultPort(for proto: String) -> Int {
        proto.lowercased().contains("tcp") ? 443 : 1194
    }
}

