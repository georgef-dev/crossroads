// The shared conformance cases for specs/ConflictFlags.tla, run against Swift.
//
// These are the same files the Python tests read, so the two platforms cannot
// drift apart. A case one of them fails is a bug in that implementation, or a
// property the spec does not yet have.

import Foundation
import Testing

import CrossroadsCore

@Test(arguments: conformanceCaseFiles)
func conformanceCase(file: URL) throws {
    let test = try load(file)
    let events = test.modelEvents
    var asserted = false

    if let expected = test.kinds {
        asserted = true
        let kinds = Dictionary(
            uniqueKeysWithValues: zip(events, classify(events)).map {
                ("\($0.id)@\($0.calendar)", $1)
            }
        )
        #expect(kinds == expected, "\(test.name)")
    }

    if let expected = test.overlaps {
        asserted = true
        // Compared as a list, not a set, so a duplicate card for the same pair shows up.
        let cards = overlaps(events).map {
            card(ids: [$0.first.id, $0.second.id], start: $0.start, end: $0.end)
        }
        let wanted = expected.map {
            card(ids: $0.ids, start: at($0.start), end: at($0.end))
        }
        #expect(cards.sorted() == wanted.sorted(), "\(test.name)")
    }

    #expect(asserted, "a case must assert kinds, overlaps, or both")
}

@Test func everyCaseNamesAProperty() throws {
    let properties = try Set(conformanceCaseFiles.map { try load($0).property })
    #expect(!properties.isEmpty, "no conformance cases found")
    #expect(properties.allSatisfy { $0.hasPrefix("ConflictFlags.") })
}

/// One card as a sortable line, so two lists of cards compare in a stable order.
private func card(ids: [String], start: Date, end: Date) -> String {
    "\(ids.sorted().joined(separator: "+")) \(start.timeIntervalSince1970) \(end.timeIntervalSince1970)"
}
