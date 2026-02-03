import Foundation

/// Represents a cookie in Playwright storage_state.json format
struct PlaywrightCookie: Codable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let expires: Double
    let httpOnly: Bool
    let secure: Bool
    let sameSite: String
}

/// Playwright storage_state.json structure
struct PlaywrightStorageState: Codable {
    let cookies: [PlaywrightCookie]
    let origins: [PlaywrightOrigin]
}

struct PlaywrightOrigin: Codable {
    let origin: String
    let localStorage: [[String: String]]
}

/// Converts HTTPCookie to Playwright storage_state.json format
enum StorageStateConverter {

    static func convert(cookies: [HTTPCookie]) -> PlaywrightStorageState {
        let playwrightCookies = cookies.map { cookie -> PlaywrightCookie in
            PlaywrightCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                expires: cookie.expiresDate?.timeIntervalSince1970 ?? -1,
                httpOnly: cookie.isHTTPOnly,
                secure: cookie.isSecure,
                sameSite: sameSiteString(from: cookie)
            )
        }

        return PlaywrightStorageState(cookies: playwrightCookies, origins: [])
    }

    private static func sameSiteString(from cookie: HTTPCookie) -> String {
        switch cookie.sameSitePolicy {
        case .sameSiteStrict: return "Strict"
        case .sameSiteLax: return "Lax"
        default: return "None"
        }
    }

    static func save(_ state: PlaywrightStorageState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(state)

        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try data.write(to: url)

        // Set restrictive permissions (owner only)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }
}
