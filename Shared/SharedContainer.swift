import Foundation

enum SharedContainer {
    static var rootURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TVOpenVPNClient", isDirectory: true)
    }

    static var profilesURL: URL {
        rootURL.appendingPathComponent(AppConstants.profileDirectoryName, isDirectory: true)
    }

    static func ensureProfileDirectory() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: profilesURL, withIntermediateDirectories: true)
    }

    static func profileURL(for fileName: String) -> URL {
        profilesURL.appendingPathComponent(sanitizedProfileFileName(fileName))
    }

    static func sanitizedProfileFileName(_ fileName: String) -> String {
        let baseName = URL(fileURLWithPath: fileName).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_ "))
        let scalarView = baseName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let sanitized = String(scalarView).trimmingCharacters(in: .whitespacesAndNewlines)
        if sanitized.lowercased().hasSuffix(".ovpn") {
            return sanitized
        }
        return sanitized.isEmpty ? "profile.ovpn" : "\(sanitized).ovpn"
    }
}
