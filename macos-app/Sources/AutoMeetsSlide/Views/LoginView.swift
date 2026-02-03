import SwiftUI

/// Login screen with Google sign-in button
struct LoginView: View {
    private var appState: AppState { AppState.shared }
    @State private var showWebView = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "doc.richtext")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("AutoMeetsSlide")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Transform your audio files and documents\ninto slide decks using Google NotebookLM")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 350)

            Button(action: { showWebView = true }) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                    Text("Sign in with Google")
                }
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("You'll be redirected to Google to authorize access")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showWebView) {
            GoogleLoginSheet(isPresented: $showWebView)
        }
    }
}

/// Sheet containing the Google login WebView
struct GoogleLoginSheet: View {
    @Binding var isPresented: Bool
    private var appState: AppState { AppState.shared }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Sign in to Google")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // WebView
            GoogleLoginWebView { cookies in
                Task {
                    await saveCookiesAndAuthenticate(cookies)
                }
            }
        }
        .frame(width: 500, height: 650)
    }

    private func saveCookiesAndAuthenticate(_ cookies: [HTTPCookie]) async {
        // Convert cookies to Playwright format
        let state = StorageStateConverter.convert(cookies: cookies)

        // Save to the path notebooklm-py expects
        do {
            try StorageStateConverter.save(state, to: AuthService.storageStatePath)
            print("Saved storage state to: \(AuthService.storageStatePath.path)")

            // Verify auth with sidecar
            await appState.checkAuth()

            if appState.isAuthenticated == true {
                isPresented = false
            }
        } catch {
            print("Failed to save storage state: \(error)")
        }
    }
}

#Preview {
    LoginView()
}
