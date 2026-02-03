import SwiftUI

/// Root view that handles authentication routing
struct ContentView: View {
    @State private var appState = AppState.shared

    var body: some View {
        Group {
            switch appState.isAuthenticated {
            case nil:
                LoadingView()
            case false:
                LoginView()
            case true:
                MainView()
            }
        }
        .task {
            await appState.checkAuth()
        }
    }
}

/// Loading indicator while checking auth
struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Checking authentication...")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}
