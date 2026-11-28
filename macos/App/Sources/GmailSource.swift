// Unread mail from Gmail.
//
// The same request Omarchy makes: the unread messages in the inbox, then each
// one's metadata. Only the sender, subject and time come back, because the app
// asks for metadata and holds no scope that could read a body.

import Foundation

import CrossroadsCore

struct GmailSource {
    private static let api = "https://gmail.googleapis.com/gmail/v1/users/me"

    /// The unread mail for every signed-in account. Each account reports its
    /// own error, so one failing never hides another's mail.
    func unread() async -> (mail: [MailMessage], errors: [String]) {
        var mail: [MailMessage] = []
        var errors: [String] = []
        for account in GoogleAuth.signedInAccounts() {
            do {
                mail += try await unread(for: account)
            } catch {
                errors.append("\(account) mail: \(error.localizedDescription)")
            }
        }
        return (mail, errors)
    }

    private func unread(for account: String) async throws -> [MailMessage] {
        let token = try await GoogleAuth.accessToken(for: account)

        struct Listing: Decodable {
            struct Item: Decodable { let id: String }
            let messages: [Item]?
        }
        let listing: Listing = try await get(
            "\(Self.api)/messages",
            token: token,
            // Gmail wants labelIds repeated, so the query is a list of items
            // rather than a dictionary.
            query: [
                URLQueryItem(name: "labelIds", value: "INBOX"),
                URLQueryItem(name: "labelIds", value: "UNREAD"),
                URLQueryItem(name: "maxResults", value: String(mailLimit)),
            ]
        )

        var found: [MailMessage] = []
        for item in (listing.messages ?? []).prefix(mailLimit) {
            let message: GmailMessage = try await get(
                "\(Self.api)/messages/\(item.id)",
                token: token,
                query: [
                    URLQueryItem(name: "format", value: "metadata"),
                    URLQueryItem(name: "metadataHeaders", value: "From"),
                    URLQueryItem(name: "metadataHeaders", value: "Subject"),
                ]
            )
            found.append(mail(from: message, account: account))
        }
        return found
    }

    private func get<Value: Decodable>(
        _ url: String,
        token: String,
        query: [URLQueryItem]
    ) async throws -> Value {
        var components = URLComponents(string: url)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw GoogleError("Gmail answered \(status)")
        }
        return try JSONDecoder().decode(Value.self, from: data)
    }
}
