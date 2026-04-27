import SwiftUI

@main
struct TVOpenVPNClientApp: App {
    @StateObject private var profileStore = ProfileStore()
    @StateObject private var vpnController = VPNController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(profileStore)
                .environmentObject(vpnController)
                .task {
                    await profileStore.reload()
                    await vpnController.load()
                }
        }
    }
}

