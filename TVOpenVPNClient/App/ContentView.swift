import SwiftUI

struct ContentView: View {
    private let sidebarButtonWidth: CGFloat = 128
    private let primaryButtonWidth: CGFloat = 212
    private let actionButtonHeight: CGFloat = 64
    private let headerHeight: CGFloat = 86

    private enum FocusTarget: Hashable {
        case refresh
        case uploadToggle
        case connect
        case profile(UUID)
        case username
        case password
    }

    @EnvironmentObject private var profileStore: ProfileStore
    @EnvironmentObject private var vpnController: VPNController
    @StateObject private var uploadServer: ProfileUploadServer
    @State private var selectedProfileID: OpenVPNProfile.ID?
    @FocusState private var focusedTarget: FocusTarget?

    init() {
        _uploadServer = StateObject(wrappedValue: ProfileUploadServer { fileName, data in
            let text = String(decoding: data, as: UTF8.self)
            _ = try OVPNParser.parse(text, profileName: fileName)
            try SharedContainer.ensureProfileDirectory()
            try data.write(to: SharedContainer.profileURL(for: fileName), options: [.atomic])
        })
    }

    var body: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: 36) {
                profileList
                    .frame(width: 430)
                    .padding(.top, 34)

                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.horizontal, 64)
            .padding(.vertical, 48)
            .background(Color(red: 0.06, green: 0.07, blue: 0.08))
            .navigationTitle("OpenVPN")
        }
        .task {
            if selectedProfileID == nil {
                selectedProfileID = profileStore.profiles.first?.id
            }
            if focusedTarget == nil {
                focusedTarget = profileStore.profiles.isEmpty ? .uploadToggle : .profile(profileStore.profiles[0].id)
            }
        }
        .onChange(of: uploadServer.lastMessage) {
            Task { await profileStore.reload() }
        }
        .onChange(of: profileStore.profiles) {
            if let selectedProfileID, profileStore.profiles.contains(where: { $0.id == selectedProfileID }) {
                focusedTarget = .profile(selectedProfileID)
            } else if let first = profileStore.profiles.first {
                selectedProfileID = first.id
                focusedTarget = .profile(first.id)
            } else {
                selectedProfileID = nil
                focusedTarget = .uploadToggle
            }
        }
    }

    private var selectedProfile: OpenVPNProfile? {
        profileStore.profiles.first { $0.id == selectedProfileID } ?? profileStore.profiles.first
    }

    private var profileList: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("Profiles")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    Task { await profileStore.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.title2.weight(.semibold))
                        .frame(width: sidebarButtonWidth, height: actionButtonHeight)
                }
                .buttonStyle(.bordered)
                .focused($focusedTarget, equals: .refresh)
            }
            .frame(height: headerHeight)

            if profileStore.profiles.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No profiles")
                        .font(.headline)
                    Text("Start upload mode and send an .ovpn file from another device.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(profileStore.profiles) { profile in
                            Button {
                                selectedProfileID = profile.id
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(profile.name)
                                        .font(.headline)
                                    Text("\(profile.summary.remoteHost):\(profile.summary.remotePort) \(profile.summary.proto.uppercased())")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                            .focused($focusedTarget, equals: .profile(profile.id))
                            .tint(profile.id == selectedProfileID ? .accentColor : .secondary)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 430)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            uploadPane
        }
        .focusSection()
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedProfile?.name ?? "OpenVPN Client")
                        .font(.largeTitle.weight(.bold))
                    Text(vpnController.status.displayName)
                        .font(.title3)
                        .foregroundStyle(statusColor)
                }
                Spacer()
                Button(connectButtonTitle) {
                    if vpnController.status == .connected || vpnController.status == .connecting {
                        vpnController.disconnect()
                    } else if let selectedProfile {
                        Task { await vpnController.connect(profile: selectedProfile) }
                    } else {
                        focusedTarget = .uploadToggle
                    }
                }
                .frame(width: primaryButtonWidth, height: actionButtonHeight)
                .buttonStyle(.borderedProminent)
                .disabled(vpnController.status == .disconnecting)
                .focused($focusedTarget, equals: .connect)
            }
            .frame(height: headerHeight)

            if let selectedProfile {
                profileSummary(selectedProfile.summary)

                if selectedProfile.summary.requiresCredentials {
                    credentialsPane
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Waiting for a profile")
                        .font(.headline)
                    Text("Start upload mode, then send an .ovpn file to the address shown on the left.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }

            errorText(profileStore.lastError)
            errorText(vpnController.lastError)

            Spacer()
        }
        .padding(34)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .focusSection()
    }

    private var uploadPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Upload")
                .font(.headline)
            Text(uploadServer.displayURL)
                .font(.system(.callout, design: .monospaced))
            HStack {
                if let message = uploadServer.lastMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    uploadServer.isRunning ? uploadServer.stop() : uploadServer.start()
                } label: {
                    Image(systemName: uploadServer.isRunning ? "stop.fill" : "play.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: sidebarButtonWidth, height: actionButtonHeight)
                }
                .buttonStyle(.borderedProminent)
                .focused($focusedTarget, equals: .uploadToggle)
            }
        }
        .padding(22)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func profileSummary(_ summary: OpenVPNProfileSummary) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 28, verticalSpacing: 14) {
            GridRow {
                label("Server")
                value("\(summary.remoteHost):\(summary.remotePort)")
            }
            GridRow {
                label("Protocol")
                value(summary.proto.uppercased())
            }
            GridRow {
                label("Routes")
                value(summary.redirectsGateway ? "Default gateway" : "\(summary.routeCount) route(s)")
            }
            GridRow {
                label("DNS")
                value(summary.dnsServers.isEmpty ? "Profile default" : summary.dnsServers.joined(separator: ", "))
            }
            GridRow {
                label("Inline material")
                value([
                    summary.hasInlineCA ? "CA" : nil,
                    summary.hasInlineCertificate ? "cert" : nil,
                    summary.hasInlinePrivateKey ? "key" : nil
                ].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .font(.body)
    }

    private var credentialsPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Credentials")
                .font(.headline)
            TextField("Username", text: $vpnController.username)
                .textContentType(.username)
                .focused($focusedTarget, equals: .username)
            SecureField("Password", text: $vpnController.password)
                .textContentType(.password)
                .focused($focusedTarget, equals: .password)
        }
        .frame(maxWidth: 520)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
    }

    private func value(_ text: String) -> some View {
        Text(text.isEmpty ? "None" : text)
            .lineLimit(2)
    }

    private func errorText(_ text: String?) -> some View {
        Group {
            if let text, !text.isEmpty {
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        }
    }

    private var statusColor: Color {
        switch vpnController.status {
        case .connected: .green
        case .connecting, .reasserting: .yellow
        case .invalid: .secondary
        default: .orange
        }
    }

    private var connectButtonTitle: String {
        if vpnController.status == .connected || vpnController.status == .connecting {
            return "Disconnect"
        }
        return selectedProfile == nil ? "Add Profile" : "Connect"
    }
}
