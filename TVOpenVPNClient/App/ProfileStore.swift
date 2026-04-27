import Foundation
import SwiftUI

@MainActor
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [OpenVPNProfile] = []
    @Published var lastError: String?

    func reload() async {
        do {
            try SharedContainer.ensureProfileDirectory()
            profiles = try loadSharedProfiles() + loadBundledProfiles()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func saveUploadedProfile(named fileName: String, data: Data) throws {
        try SharedContainer.ensureProfileDirectory()
        let url = SharedContainer.profileURL(for: fileName)
        try data.write(to: url, options: [.atomic])
    }

    private func loadSharedProfiles() throws -> [OpenVPNProfile] {
        guard FileManager.default.fileExists(atPath: SharedContainer.profilesURL.path) else {
            return []
        }

        let urls = try FileManager.default.contentsOfDirectory(
            at: SharedContainer.profilesURL,
            includingPropertiesForKeys: nil
        )

        return urls
            .filter { $0.pathExtension.caseInsensitiveCompare("ovpn") == .orderedSame }
            .compactMap { url in
                do {
                    let text = try String(contentsOf: url, encoding: .utf8)
                    let name = url.deletingPathExtension().lastPathComponent
                    return try OpenVPNProfile(name: name, fileName: url.lastPathComponent, source: .sharedContainer, ovpn: text)
                } catch {
                    lastError = "Skipped \(url.lastPathComponent): \(error.localizedDescription)"
                    return nil
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadBundledProfiles() -> [OpenVPNProfile] {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ovpn", subdirectory: "Profiles") else {
            return []
        }

        return urls.compactMap { url in
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let name = url.deletingPathExtension().lastPathComponent
            return try? OpenVPNProfile(name: name, fileName: url.lastPathComponent, source: .bundled, ovpn: text)
        }
    }
}

