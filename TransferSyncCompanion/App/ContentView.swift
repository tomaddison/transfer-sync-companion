import SwiftUI

struct ContentView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            switch authManager.authState {
            case .unknown:
                LoadingView(message: "Loading...")
            case .loggedOut:
                LoginView()
            case .loggingIn:
                AuthLoadingView()
            case .loggedIn:
                FinderSyncGate { HomeView() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.companionMain)
    }
}
