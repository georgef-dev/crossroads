// Reading the shared conformance cases. See conformance/README.md.

import Foundation

import CrossroadsCore

/// One modeled day, as minutes past its start. Which day it is never matters
/// to the rules, so the Swift side needs no calendar or time zone.
func at(_ clock: String) -> Date {
    let parts = clock.split(separator: ":")
    precondition(parts.count == 2, "a time is HH:MM, not \(clock)")
    guard let hours = Int(parts[0]), let minutes = Int(parts[1]) else {
        preconditionFailure("a time is HH:MM, not \(clock)")
    }
    return Date(timeIntervalSince1970: TimeInterval(hours * 3600 + minutes * 60))
}

struct ConformanceCase: Decodable {
    struct Occurrence: Decodable {
        let id: String
        let calendar: String
        let tag: Tag
        let start: String
        let end: String
        let allDay: Bool
        let status: Status
    }

    struct Card: Decodable {
        let ids: [String]
        let start: String
        let end: String
    }

    let property: String
    let name: String
    let events: [Occurrence]
    /// Present when the case asserts each event's kind, keyed `id@calendar`.
    let kinds: [String: Kind]?
    /// Present when the case asserts the overlap cards. Empty means no cards.
    let overlaps: [Card]?

    var modelEvents: [Event] {
        events.map { occurrence in
            Event(
                id: occurrence.id,
                calendar: occurrence.calendar,
                tag: occurrence.tag,
                title: occurrence.id,
                start: at(occurrence.start),
                end: at(occurrence.end),
                isAllDay: occurrence.allDay,
                status: occurrence.status
            )
        }
    }
}

/// The repository root, found from this file rather than from the working
/// directory, so `swift test` works from anywhere. The cases sit outside the
/// package, at the root, because both platforms read them.
private let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()  // CrossroadsCoreTests
    .deletingLastPathComponent()  // Tests
    .deletingLastPathComponent()  // macos
    .deletingLastPathComponent()  // the root

/// Every case file, in a stable order so a failure always names the same case.
let conformanceCaseFiles: [URL] = {
    let folder = repositoryRoot.appendingPathComponent("conformance")
    let contents = try! FileManager.default.contentsOfDirectory(
        at: folder,
        includingPropertiesForKeys: nil
    )
    return contents.filter { $0.pathExtension == "json" }.sorted { $0.path < $1.path }
}()

func load(_ file: URL) throws -> ConformanceCase {
    try JSONDecoder().decode(ConformanceCase.self, from: Data(contentsOf: file))
}
