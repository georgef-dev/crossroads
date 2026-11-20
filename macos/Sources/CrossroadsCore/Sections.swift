// What the panel lists, in order, and what opens when you press Return.
// Ported from the modal part of omarchy/plugin/Model.js.

import Foundation

/// Mail shows as a grid of two cards per row; everything else is a list.
public let mailColumns = 2

public enum SectionKey: String, Sendable {
    /// Overlap cards in range. Hidden when there are none.
    case overlaps
    /// Reminders that need attention. Hidden when there are none.
    case reminders
    /// Today's strip.
    case today
    case mail
    /// Search results among every fetched event.
    case events
}

public enum ItemValue: Hashable, Sendable {
    case event(FlaggedEvent)
    case card(OverlapCard)
    case reminder(FlaggedReminder)
    case mail(MailMessage)
}

/// One row of the panel. Every item carries its position in the whole list, so
/// keyboard selection can move across sections.
public struct Item: Hashable, Sendable {
    public let value: ItemValue
    public let index: Int

    public init(value: ItemValue, index: Int) {
        self.value = value
        self.index = index
    }
}

public struct Section: Hashable, Sendable {
    public let key: SectionKey
    public let columns: Int
    public let items: [Item]

    public init(key: SectionKey, columns: Int, items: [Item]) {
        self.key = key
        self.columns = columns
        self.items = items
    }
}

/// What the panel lists, in order.
public func panelSections(
    _ snapshot: Snapshot?,
    now: Date,
    days: Int,
    query: String = "",
    calendar: Calendar = .current
) -> [Section] {
    let snapshot = snapshot ?? Snapshot()
    let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    var found: [(key: SectionKey, values: [ItemValue])]
    if wanted.isEmpty {
        found = [
            (
                .overlaps,
                cardsInRange(snapshot.overlaps, now: now, days: days, calendar: calendar)
                    .map(ItemValue.card)
            ),
            (.reminders, snapshot.reminders.map(ItemValue.reminder)),
            (
                .today,
                eventsInRange(snapshot.events, now: now, days: 0, calendar: calendar)
                    .map(ItemValue.event)
            ),
            (.mail, snapshot.mail.map(ItemValue.mail)),
        ]
        // Today and mail keep their place when empty, so the view keeps its
        // shape. Overlaps and reminders appear only when there are any.
        let onlyWhenPresent: Set<SectionKey> = [.overlaps, .reminders]
        found = found.filter { !onlyWhenPresent.contains($0.key) || !$0.values.isEmpty }
    } else {
        found = [
            (
                .events,
                snapshot.events
                    .filter { matches(wanted, [$0.event.title, $0.calendarName]) }
                    .map(ItemValue.event)
            ),
            (
                .reminders,
                snapshot.reminders
                    .filter { matches(wanted, [$0.reminder.title, $0.reminder.list]) }
                    .map(ItemValue.reminder)
            ),
            (
                .mail,
                snapshot.mail
                    .filter { matches(wanted, [$0.subject, $0.sender, $0.account]) }
                    .map(ItemValue.mail)
            ),
        ]
        found = found.filter { !$0.values.isEmpty }
    }

    var index = 0
    return found.map { section in
        let items = section.values.map { value -> Item in
            let item = Item(value: value, index: index)
            index += 1
            return item
        }
        return Section(
            key: section.key,
            columns: section.key == .mail ? mailColumns : 1,
            items: items
        )
    }
}

private func matches(_ query: String, _ values: [String]) -> Bool {
    values.contains { $0.lowercased().contains(query) }
}

public func itemCount(_ sections: [Section]) -> Int {
    sections.reduce(0) { $0 + $1.items.count }
}

public func itemAt(_ sections: [Section], index: Int) -> Item? {
    for section in sections {
        for item in section.items where item.index == index {
            return item
        }
    }
    return nil
}

/// Where an item opens. A card opens its first event.
public func linkOf(_ item: Item?) -> String {
    guard let item else { return "" }
    let link: String
    switch item.value {
    case .card(let card): link = card.events.first?.event.link ?? ""
    case .event(let flagged): link = flagged.event.link
    case .reminder(let flagged): link = flagged.reminder.link
    case .mail(let message): link = message.link
    }
    return safeLink(link)
}

/// Links come from outside, so only the services Crossroads reads can open.
/// The prefixes are the whole rule: anything that does not start with one of
/// them, host and path included, does not open.
private let safeLinkPrefixes = [
    "https://www.google.com/calendar/",
    "https://calendar.google.com/",
    "https://mail.google.com/",
    "https://www.icloud.com/calendar/",
]

public func safeLink(_ link: String) -> String {
    guard safeLinkPrefixes.contains(where: { link.hasPrefix($0) }) else { return "" }
    // No whitespace and no control characters, so a link stays one argument.
    let suspect = link.unicodeScalars.contains {
        $0.properties.isWhitespace || $0.value <= 0x1F || $0.value == 0x7F
    }
    return suspect ? "" : link
}

/// What the footer says about freshness.
public enum StatusLine: Hashable, Sendable {
    case refreshing
    case failed(at: Date?)
    case updated(at: Date)
    case fetching
}

public func statusLine(refreshing: Bool, snapshot: Snapshot?, runFailed: Bool) -> StatusLine {
    if refreshing { return .refreshing }
    if runFailed { return .failed(at: snapshot?.fetchedAt) }
    if let fetchedAt = snapshot?.fetchedAt { return .updated(at: fetchedAt) }
    return .fetching
}
