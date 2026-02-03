import Foundation
import WebKit

/// Manages authentication state and storage paths
enum AuthService {

    /// Default path where notebooklm-py expects storage_state.json
    static var storageStatePath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".notebooklm/storage_state.json")
    }

    /// Check if storage state file exists and is recent enough
    static func hasValidStorageState() -> Bool {
        let url = storageStatePath
        guard FileManager.default.fileExists(atPath: url.path) else {
            return false
        }

        // Check if file was modified within last 24 hours
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date
        else {
            return false
        }

        let age = Date().timeIntervalSince(modDate)
        return age < 86400  // 24 hours
    }

    /// Clear stored authentication
    static func clearStorageState() {
        try? FileManager.default.removeItem(at: storageStatePath)
    }

    /// Holder for the silent auth checker to prevent deallocation
    private static var silentAuthChecker: SilentAuthChecker?

    /// Try to authenticate by loading NotebookLM in a hidden WebView
    /// If already logged in (via Safari cookies), extract and save cookies
    @MainActor
    static func tryAuthenticateWithSafariCookies() async -> Bool {
        Log.auth.info("Attempting silent auth with hidden WebView...")

        return await withCheckedContinuation { continuation in
            silentAuthChecker = SilentAuthChecker { success in
                silentAuthChecker = nil  // Release after completion
                continuation.resume(returning: success)
            }
            silentAuthChecker?.start()
        }
    }
}

/// Helper class to check auth silently using a hidden WKWebView
@MainActor
class SilentAuthChecker: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private var completion: ((Bool) -> Void)?
    private var hasCompleted = false
    private var redirectCount = 0

    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
        super.init()
    }

    func start() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        let url = URL(string: "https://notebooklm.google.com/")!
        Log.auth.info("Loading NotebookLM in hidden WebView...")
        webView.load(URLRequest(url: url))

        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            self?.completeWith(success: false, reason: "Timeout")
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let url = webView.url else { return }
        Log.auth.info("WebView finished loading: \(url.absoluteString)")

        // Check if we're on the NotebookLM page (not accounts.google.com)
        let isLoggedIn = url.host?.contains("notebooklm.google.com") == true &&
                        !url.absoluteString.contains("accounts.google")

        if isLoggedIn {
            Log.auth.info("User is logged in, extracting cookies...")
            extractCookiesAndComplete(from: webView)
        } else if url.host?.contains("accounts.google") == true {
            Log.auth.info("Redirected to Google accounts - user not logged in")
            completeWith(success: false, reason: "Not logged in")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Log.auth.error("WebView navigation failed: \(error.localizedDescription)")
        completeWith(success: false, reason: "Navigation error")
    }

    private func extractCookiesAndComplete(from webView: WKWebView) {
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            let relevantCookies = cookies.filter { cookie in
                cookie.domain.contains("google.com") || cookie.domain.contains("notebooklm")
            }

            Log.auth.info("Extracted \(relevantCookies.count) cookies from hidden WebView")

            let state = StorageStateConverter.convert(cookies: relevantCookies)
            do {
                try StorageStateConverter.save(state, to: AuthService.storageStatePath)
                Log.auth.info("Saved cookies to storage_state.json")
                self?.completeWith(success: true, reason: "Authenticated")
            } catch {
                Log.auth.error("Failed to save cookies: \(error.localizedDescription)")
                self?.completeWith(success: false, reason: "Save error")
            }
        }
    }

    private func completeWith(success: Bool, reason: String) {
        guard !hasCompleted else { return }
        hasCompleted = true
        Log.auth.info("Silent auth completed: success=\(success), reason=\(reason)")
        webView?.stopLoading()
        webView = nil
        completion?(success)
        completion = nil
    }
}
