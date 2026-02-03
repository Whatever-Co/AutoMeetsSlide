import SwiftUI
import WebKit

/// WKWebView wrapper for Google authentication
struct GoogleLoginWebView: NSViewRepresentable {
    let onAuthenticated: ([HTTPCookie]) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only load if not already loaded
        if webView.url == nil {
            let url = URL(string: "https://notebooklm.google.com/")!
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: GoogleLoginWebView
        private var hasExtractedCookies = false

        init(_ parent: GoogleLoginWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let url = webView.url else { return }

            // Check if user has logged in (URL should be notebooklm.google.com without accounts redirect)
            let isLoggedIn = url.host?.contains("notebooklm.google.com") == true &&
                            !url.absoluteString.contains("accounts.google")

            if isLoggedIn && !hasExtractedCookies {
                extractCookies(from: webView)
            }
        }

        private func extractCookies(from webView: WKWebView) {
            hasExtractedCookies = true

            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                // Filter for Google-related cookies
                let relevantCookies = cookies.filter { cookie in
                    cookie.domain.contains("google.com") ||
                    cookie.domain.contains("notebooklm")
                }

                print("Extracted \(relevantCookies.count) cookies")

                DispatchQueue.main.async {
                    self?.parent.onAuthenticated(relevantCookies)
                }
            }
        }
    }
}
