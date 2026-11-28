// Turning a Gmail message into the mail the panel shows.
//
// Pure, and working from the decoded JSON rather than from the network, so it
// is tested against recorded responses. Ported from mail_from_gmail in
// omarchy/src/crossroads/google.py, so both platforms read a message the same
// way.
//
// Crossroads asks Gmail only for metadata, so a message body is never fetched
// and cannot appear here.

import Foundation

/// At most this many unread messages are fetched, as on Omarchy.
public let mailLimit = 25

/// One message as Gmail's `messages.get` returns it with `format=metadata`.
public struct GmailMessage: Decodable, Sendable {
    public struct Payload: Decodable, Sendable {
        public struct Header: Decodable, Sendable {
            public let name: String
            public let value: String
        }
        public let headers: [Header]?
    }

    public let id: String
    public let threadId: String
    /// Milliseconds since the epoch, as a string, which is how Gmail sends it.
    public let internalDate: String?
    public let payload: Payload?
}

/// The mail the panel shows, for one account.
public func mail(from message: GmailMessage, account: String) -> MailMessage {
    let headers = Dictionary(
        (message.payload?.headers ?? []).map { ($0.name.lowercased(), $0.value) },
        uniquingKeysWith: { first, _ in first }
    )
    return MailMessage(
        id: message.id,
        subject: headers["subject"] ?? "",
        sender: headers["from"] ?? "",
        account: account,
        received: received(message.internalDate),
        link: gmailLink(account: account, threadID: message.threadId)
    )
}

private func received(_ internalDate: String?) -> Date {
    guard let milliseconds = internalDate.flatMap(Double.init) else { return .distantPast }
    return Date(timeIntervalSince1970: milliseconds / 1000)
}

/// Where the message opens, which is its thread in the right account's inbox.
func gmailLink(account: String, threadID: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-._~")
    let user = account.addingPercentEncoding(withAllowedCharacters: allowed) ?? account
    return "https://mail.google.com/mail/?authuser=\(user)#all/\(threadID)"
}
