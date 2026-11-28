// Signing in to Google, and keeping the token.
//
// The same desktop OAuth flow Omarchy uses (see omarchy/src/crossroads/google.py
// and omarchy/docs/accounts.md): your own OAuth client, consent in the browser,
// and a loopback redirect to a port on this machine. The refresh token goes
// into the Keychain; the client secret never leaves it either.
//
// Read-only scopes, and Gmail metadata only, so a message body is never
// fetched.

import AppKit
import CryptoKit
import Foundation

enum GoogleAuth {
    static let scopes = [
        "https://www.googleapis.com/auth/calendar.readonly",
        "https://www.googleapis.com/auth/gmail.metadata",
    ]

    /// The OAuth client, as Google's downloaded JSON holds it.
    struct Client: Decodable {
        let clientID: String
        let clientSecret: String
        let authURI: URL
        let tokenURI: URL

        private enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case clientSecret = "client_secret"
            case authURI = "auth_uri"
            case tokenURI = "token_uri"
        }

        /// Google wraps the client in an "installed" or "web" object.
        private struct File: Decodable {
            let installed: Client?
            let web: Client?
        }

        static func decode(_ data: Data) throws -> Client {
            if let file = try? JSONDecoder().decode(File.self, from: data),
               let client = file.installed ?? file.web {
                return client
            }
            return try JSONDecoder().decode(Client.self, from: data)
        }
    }

    /// Reads a client_secret.json and keeps it, so sign-in can use it later.
    static func saveClient(from file: URL) throws {
        let client = try Client.decode(try Data(contentsOf: file))
        let stored = try JSONEncoder().encode([
            "client_id": client.clientID,
            "client_secret": client.clientSecret,
            "auth_uri": client.authURI.absoluteString,
            "token_uri": client.tokenURI.absoluteString,
        ])
        try Keychain.put(Keychain.googleClient, account: "default", value: String(decoding: stored, as: UTF8.self))
    }

    static var hasClient: Bool {
        Keychain.get(Keychain.googleClient, account: "default") != nil
    }

    /// Every account signed in so far.
    static func signedInAccounts() -> [String] {
        guard let stored = Keychain.get(Keychain.googleToken, account: accountListKey),
              let accounts = try? JSONDecoder().decode([String].self, from: Data(stored.utf8))
        else { return [] }
        return accounts
    }

    /// Consent in the browser, then keep the refresh token.
    static func signIn(account: String) async throws {
        let client = try storedClient()
        let verifier = randomString(64)
        let state = randomString(16)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let listener = try LoopbackListener()
        defer { listener.stop() }

        var consent = URLComponents(url: client.authURI, resolvingAgainstBaseURL: false)!
        consent.queryItems = [
            .init(name: "client_id", value: client.clientID),
            .init(name: "redirect_uri", value: listener.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scopes.joined(separator: " ")),
            // Offline, so Crossroads keeps working without signing in again.
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
            .init(name: "login_hint", value: account),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
        ]
        NSWorkspace.shared.open(consent.url!)

        let answer = try await listener.wait()
        guard answer["state"] == state, let code = answer["code"] else {
            throw GoogleError(answer["error"].map { "sign-in failed: \($0)" } ?? "sign-in failed")
        }

        let tokens = try await post(to: client.tokenURI, form: [
            "client_id": client.clientID,
            "client_secret": client.clientSecret,
            "code": code,
            "code_verifier": verifier,
            "redirect_uri": listener.redirectURI,
            "grant_type": "authorization_code",
        ])
        guard let refresh = tokens["refresh_token"] as? String,
              let access = tokens["access_token"] as? String
        else { throw GoogleError("Google did not return a token") }

        // Signing in as somebody else would quietly read the wrong account.
        let signedIn = try await profileAddress(accessToken: access)
        guard signedIn.lowercased() == account.lowercased() else {
            throw GoogleError("signed in as \(signedIn.isEmpty ? "an unknown account" : signedIn), expected \(account)")
        }

        try Keychain.put(Keychain.googleToken, account: account, value: refresh)
        try remember(account)
    }

    static func signOut(account: String) throws {
        Keychain.remove(Keychain.googleToken, account: account)
        let left = signedInAccounts().filter { $0 != account }
        try Keychain.put(
            Keychain.googleToken,
            account: accountListKey,
            value: String(decoding: try JSONEncoder().encode(left), as: UTF8.self)
        )
    }

    /// A short-lived access token for one account.
    static func accessToken(for account: String) async throws -> String {
        guard let refresh = Keychain.get(Keychain.googleToken, account: account) else {
            throw GoogleError("\(account) is not signed in")
        }
        let client = try storedClient()
        let tokens = try await post(to: client.tokenURI, form: [
            "client_id": client.clientID,
            "client_secret": client.clientSecret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        guard let access = tokens["access_token"] as? String else {
            throw GoogleError("could not refresh \(account)")
        }
        return access
    }

    // ---- The pieces.

    /// Which accounts are signed in, kept beside the tokens themselves.
    private static let accountListKey = "accounts"

    private static func remember(_ account: String) throws {
        var accounts = signedInAccounts()
        guard !accounts.contains(account) else { return }
        accounts.append(account)
        try Keychain.put(
            Keychain.googleToken,
            account: accountListKey,
            value: String(decoding: try JSONEncoder().encode(accounts), as: UTF8.self)
        )
    }

    private static func storedClient() throws -> Client {
        guard let stored = Keychain.get(Keychain.googleClient, account: "default") else {
            throw GoogleError("no Google OAuth client yet. See macos/README.md.")
        }
        return try Client.decode(Data(stored.utf8))
    }

    private static func profileAddress(accessToken: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/profile")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return "" }
        let profile = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (profile?["emailAddress"] as? String) ?? ""
    }

    private static func post(to url: URL, form: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            // The body of a failed token request can hold the secret, so only
            // the status is reported.
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw GoogleError("Google refused the token request (\(code))")
        }
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func randomString(_ bytes: Int) -> String {
        var raw = Data(count: bytes)
        _ = raw.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!) }
        return raw.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

struct GoogleError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
