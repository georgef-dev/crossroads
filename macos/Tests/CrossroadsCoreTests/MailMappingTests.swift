// Reading a Gmail message. The Omarchy equivalent is in omarchy/tests/test_google.py.

import Foundation
import Testing

import CrossroadsCore

@Suite("Mail mapping")
struct MailMappingTests {
    func message(_ json: String) throws -> GmailMessage {
        try JSONDecoder().decode(GmailMessage.self, from: Data(json.utf8))
    }

    @Test("a message keeps its sender, subject, thread and time")
    func plainMessage() throws {
        let decoded = try message("""
        {
          "id": "m1",
          "threadId": "t1",
          "internalDate": "1763390400000",
          "payload": { "headers": [
            { "name": "From", "value": "School <office@school.org>" },
            { "name": "Subject", "value": "Early pickup Friday" }
          ] }
        }
        """)

        let item = mail(from: decoded, account: "me@gmail.com")

        #expect(item.id == "m1")
        #expect(item.sender == "School <office@school.org>")
        #expect(item.subject == "Early pickup Friday")
        #expect(item.account == "me@gmail.com")
        #expect(item.received == Date(timeIntervalSince1970: 1_763_390_400))
        #expect(item.link == "https://mail.google.com/mail/?authuser=me%40gmail.com#all/t1")
    }

    @Test("headers are matched whatever their case")
    func headerCase() throws {
        let decoded = try message("""
        {"id":"m","threadId":"t","internalDate":"0",
         "payload":{"headers":[{"name":"FROM","value":"a@b.com"},{"name":"subject","value":"Hi"}]}}
        """)
        let item = mail(from: decoded, account: "me@gmail.com")
        #expect(item.sender == "a@b.com")
        #expect(item.subject == "Hi")
    }

    @Test("a message with no subject or sender still maps")
    func missingHeaders() throws {
        let decoded = try message("""
        {"id":"m","threadId":"t","internalDate":"0","payload":{"headers":[]}}
        """)
        let item = mail(from: decoded, account: "me@gmail.com")
        #expect(item.subject == "")
        #expect(item.sender == "")
    }

    @Test("a message with no payload at all does not throw")
    func missingPayload() throws {
        let decoded = try message("""
        {"id":"m","threadId":"t"}
        """)
        let item = mail(from: decoded, account: "me@gmail.com")
        #expect(item.subject == "")
        #expect(item.received == .distantPast)
    }

    @Test("the link opens the thread in the right account, and is a link we allow")
    func links() throws {
        let decoded = try message("""
        {"id":"m","threadId":"t1","internalDate":"0","payload":{"headers":[]}}
        """)
        let item = mail(from: decoded, account: "first.last+tag@example.com")

        #expect(item.link.contains("authuser=first.last%2Btag%40example.com"))
        // The panel refuses to open anything it does not recognise, so the
        // link it builds has to be one of those.
        #expect(safeLink(item.link) == item.link)
    }

    @Test("mail is shown newest first, whatever order Gmail returns it in")
    func ordering() throws {
        func at(_ milliseconds: Int, _ id: String) throws -> MailMessage {
            try mail(
                from: message("""
                {"id":"\(id)","threadId":"\(id)","internalDate":"\(milliseconds)",
                 "payload":{"headers":[]}}
                """),
                account: "me@gmail.com"
            )
        }
        let snapshot = buildSnapshot(
            events: [],
            mail: [try at(2000, "middle"), try at(3000, "newest"), try at(1000, "oldest")]
        )
        #expect(snapshot.mail.map(\.id) == ["newest", "middle", "oldest"])
    }
}
