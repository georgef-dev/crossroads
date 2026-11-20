// Property tests derived from the invariants in specs/ConflictFlags.tla.
//
// The properties are restated from the spec's English lines with their own
// helpers, so they don't share the logic under test. These match the Python
// property tests one for one.

import Foundation
import Testing

import CrossroadsCore

@Suite("ConflictFlags properties")
struct ConflictFlagsPropertyTests {
    @Test("TypeOK: every event in the view has one of the three kinds")
    func typeOK() {
        forEachGeneratedEventList { events in
            let kinds = classify(events)
            #expect(kinds.count == events.count, "\(events)")
            #expect(kinds.allSatisfy { Kind.allCases.contains($0) }, "\(events)")
        }
    }

    @Test("AllDayNeverFlagged: all-day events are never flagged")
    func allDayNeverFlagged() {
        forEachGeneratedEventList { events in
            for (event, kind) in zip(events, classify(events)) where event.isAllDay {
                #expect(kind == .none, "\(events)")
            }
        }
    }

    @Test("InactiveNeverFlagged: declined and cancelled events are never flagged")
    func inactiveNeverFlagged() {
        forEachGeneratedEventList { events in
            for (event, kind) in zip(events, classify(events)) where !isActive(event) {
                #expect(kind == .none, "\(events)")
            }
        }
    }

    @Test("OverlapsAreFlagged: any two timed events that overlap are both flagged")
    func overlapsAreFlagged() {
        forEachGeneratedEventList { events in
            let kinds = classify(events)
            for (i, a) in events.enumerated() {
                for (j, b) in events.enumerated() where realOverlap(a, b) {
                    #expect(kinds[i] != .none, "\(events)")
                    #expect(kinds[j] != .none, "\(events)")
                }
            }
        }
    }

    @Test("FlagsNeedRealOverlap: touching ends and an event's own copies don't count")
    func flagsNeedRealOverlap() {
        forEachGeneratedEventList { events in
            for (event, kind) in zip(events, classify(events)) where kind != .none {
                #expect(events.contains { realOverlap(event, $0) }, "\(events)")
            }
        }
    }

    @Test("CrossTagShowsMixed: an event overlapping the other tag shows as personal + work")
    func crossTagShowsMixed() {
        forEachGeneratedEventList { events in
            for (event, kind) in zip(events, classify(events)) {
                let crossesTags = events.contains { realOverlap(event, $0) && $0.tag != event.tag }
                if crossesTags {
                    #expect(kind == .mixed, "\(events)")
                }
            }
        }
    }

    @Test("MixedNeedsCrossTag: only a cross-tag overlap shows as personal + work")
    func mixedNeedsCrossTag() {
        forEachGeneratedEventList { events in
            for (event, kind) in zip(events, classify(events)) where kind == .mixed {
                #expect(
                    events.contains { realOverlap(event, $0) && $0.tag != event.tag },
                    "\(events)"
                )
            }
        }
    }

    @Test("CardsAreRealOverlaps: every card shows two different events that really overlap")
    func cardsAreRealOverlaps() {
        forEachGeneratedEventList { events in
            for card in overlaps(events) {
                #expect(realOverlap(card.first, card.second), "\(events)")
            }
        }
    }

    @Test("OneCardPerOverlap: one card per real overlap, however many calendars")
    func oneCardPerOverlap() {
        forEachGeneratedEventList { events in
            let cards = overlaps(events)
            for a in events {
                for b in events where realOverlap(a, b) {
                    let matching = cards.filter {
                        Set([$0.first.id, $0.second.id]) == Set([a.id, b.id])
                    }
                    #expect(matching.count == 1, "\(events)")
                }
            }
        }
    }

    @Test("CardWindowIsTheOverlap: a card's window is when both events are happening")
    func cardWindowIsTheOverlap() {
        forEachGeneratedEventList { events in
            for card in overlaps(events) {
                #expect(card.start == max(card.first.start, card.second.start), "\(events)")
                #expect(card.end == min(card.first.end, card.second.end), "\(events)")
            }
        }
    }
}

/// Declined and cancelled events are never flagged; tentative ones can be.
private func isActive(_ event: Event) -> Bool {
    event.status == .accepted || event.status == .tentative
}

/// Two different events, both timed and active, whose times really overlap.
private func realOverlap(_ a: Event, _ b: Event) -> Bool {
    a.id != b.id
        && !a.isAllDay
        && !b.isAllDay
        && isActive(a)
        && isActive(b)
        && a.start < b.end
        && b.start < a.end
}
