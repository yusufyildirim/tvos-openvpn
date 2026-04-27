# TVOpenVPNClient

A native tvOS 17+ OpenVPN client shell built around `.ovpn` profiles.

The project contains:

- `TVOpenVPNClient`: a SwiftUI tvOS app for importing/selecting profiles and starting/stopping the VPN.
- `PacketTunnel`: a `NEPacketTunnelProvider` extension that owns tunnel lifecycle.
- `Shared`: profile parsing, app-group paths, and models used by both targets.
- A LAN upload server in the tvOS app. Start it in the app, then POST a `.ovpn` file from another device on the same network:

```sh
curl --data-binary @client.ovpn http://APPLE_TV_IP:8080/profiles/client.ovpn
```

## Required Signing

Change these placeholders before installing on a device:

- Bundle ID prefix: `com.yusuf.TVOpenVPNClient`
- App Group: `group.com.yusuf.TVOpenVPNClient`
- Enable Network Extensions / Packet Tunnel entitlement for the app and extension in your Apple Developer account.

Simulator builds can be checked with code signing disabled:

```sh
xcodebuild -project TVOpenVPNClient.xcodeproj \
  -scheme TVOpenVPNClient \
  -sdk appletvsimulator \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

## OpenVPN Core

Apple exposes the packet tunnel plumbing on tvOS 17+, but OpenVPN itself is not a system protocol. The packet tunnel extension uses [Partout](https://github.com/partout-io/partout) for OpenVPN parsing, cryptography, socket handling, and packet forwarding.

The project links Partout through SwiftPM. Partout also resolves WireGuard support transitively, so tvOS simulator builds exclude `x86_64` and build the arm64 simulator slice.
