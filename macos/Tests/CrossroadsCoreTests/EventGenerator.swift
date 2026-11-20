// Generated event lists for the property tests.
//
// Python uses Hypothesis. Swift has no equivalent in the toolchain, so this is
// a seeded generator: the same seed always makes the same lists, which keeps a
// failure reproducible.

import Foundation

import CrossroadsCore

/// A small, fast, seeded generator. Any decent one would do; this one needs no
/// dependency. See https://prng.di.unimi.it/splitmix64.c
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private let ids = ["e1", "e2", "e3", "e4"]
private let calendars: [(name: String, tag: Tag)] = [
    ("family", .personal),
    ("kids", .personal),
    ("work", .work),
]

/// Half an hour, the slot every generated event starts and ends on.
private let slot: TimeInterval = 30 * 60

/// A small event list where copies of one event share their time, as the spec requires.
func generateEvents(using generator: inout SeededGenerator) -> [Event] {
    var shapes: [String: (start: Date, end: Date, isAllDay: Bool)] = [:]
    for id in ids {
        let start = Int.random(in: 0...6, using: &generator)
        let length = Int.random(in: 1...4, using: &generator)
        shapes[id] = (
            start: Date(timeIntervalSince1970: Double(start) * slot),
            end: Date(timeIntervalSince1970: Double(start + length) * slot),
            isAllDay: Bool.random(using: &generator)
        )
    }

    // Up to six occurrences, each a different event on a different calendar.
    var available = ids.flatMap { id in calendars.map { (id: id, calendar: $0) } }
    available.shuffle(using: &generator)
    let count = Int.random(in: 0...6, using: &generator)

    return available.prefix(count).map { occurrence in
        let shape = shapes[occurrence.id]!
        return Event(
            id: occurrence.id,
            calendar: occurrence.calendar.name,
            tag: occurrence.calendar.tag,
            title: occurrence.id,
            start: shape.start,
            end: shape.end,
            isAllDay: shape.isAllDay,
            status: Status.allCases.randomElement(using: &generator)!
        )
    }
}

/// Runs `check` over many generated event lists. The seed is fixed, so every
/// run tests the same lists and a failure always reproduces.
func forEachGeneratedEventList(
    seed: UInt64 = 0x0C05_5DAD,
    rounds: Int = 400,
    _ check: ([Event]) -> Void
) {
    var generator = SeededGenerator(seed: seed)
    for _ in 0..<rounds {
        check(generateEvents(using: &generator))
    }
}
