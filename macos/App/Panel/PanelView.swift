// The panel: a header with the search field and the range, the sections, and a
// footer saying how fresh the data is.
//
// Every decision about what to show, and what a key does, comes from
// CrossroadsCore. This file only draws it.

import SwiftUI

import CrossroadsCore

struct PanelView: View {
    @Bindable var model: AppModel
    /// Offscreen rendering cannot draw a material, a scroll view's contents or
    /// a text field, so the screenshot asks for still stand-ins instead. The
    /// rows themselves are the same ones the panel draws.
    var forScreenshot = false

    /// onKeyPress only fires while the panel holds focus, and the search field
    /// is the only thing that can take it. Settings has no field, and vim's
    /// normal mode deliberately leaves it, so the panel itself has to be able
    /// to hold focus too, or no key would reach the model at all.
    private enum Target: Hashable {
        case search
        case panel
    }

    @FocusState private var focus: Target?

    var body: some View {
        VStack(spacing: 0) {
            if model.showingSettings {
                SettingsPanelView(model: model, forScreenshot: forScreenshot)
            } else {
                header
                Divider()
                list
                footer
            }
        }
        .frame(width: 760, height: 580)
        .background {
            // The material follows the system; the wash gives the panel a
            // little depth without fighting it.
            Rectangle()
                .fill(forScreenshot
                    ? AnyShapeStyle(Color(light: 0xF5F5F7, dark: 0x1F2230))
                    : AnyShapeStyle(.regularMaterial))
                .overlay(
                    LinearGradient(
                        colors: [Palette.personal.opacity(0.10), Palette.work.opacity(0.08)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .panel)
        .onKeyPress(phases: .down) { press in
            handled(press) ? .handled : .ignored
        }
        .onAppear { takeFocus() }
        .onChange(of: model.showingSettings) { takeFocus() }
        .onChange(of: model.mode) { takeFocus() }
    }

    /// The search field types; everything else moves. Whichever is right for
    /// the current view, something is always focused.
    private func takeFocus() {
        focus = model.showingSettings || model.mode == .normal ? .panel : .search
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                if forScreenshot {
                    Text("Search events, reminders and mail")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    Spacer()
                } else {
                    TextField("Search events, reminders and mail", text: $model.query)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($focus, equals: .search)
                }
                if model.flagged > 0 {
                    CountBadge(count: model.flagged)
                }
            }
            RangePicker(days: model.days)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var sections: some View {
        ForEach(model.sections, id: \.key) { section in
            SectionView(section: section, selection: model.selection)
        }
        if itemCount(model.sections) == 0 {
            EmptyState(searching: !model.query.isEmpty)
        }
    }

    @ViewBuilder
    private var list: some View {
        if forScreenshot {
            VStack(alignment: .leading, spacing: 20) { sections }
                .padding(18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) { sections }
                        .padding(18)
                }
                .onChange(of: model.selection) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        scroller.scrollTo(model.selection, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(freshness)
                .font(.caption)
                .foregroundStyle(.secondary)
            if !model.snapshot.errors.isEmpty {
                Text("· \(model.snapshot.errors.count) problem\(model.snapshot.errors.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(Palette.urgent)
            }
            Spacer()
            if model.settings.keys == .vim {
                ModeBadge(mode: model.mode)
            }
            Hint("⌃,", "settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(Color.primary.opacity(0.04))
    }

    private var statusColor: Color {
        switch model.status {
        case .refreshing, .fetching: .secondary
        case .failed: Palette.urgent
        case .updated: Palette.ok
        }
    }

    private var freshness: String {
        switch model.status {
        case .refreshing: "Refreshing…"
        case .fetching: "Fetching…"
        case .updated(let at): "Updated \(at.formatted(date: .omitted, time: .shortened))"
        case .failed(let at):
            if let at { "Update failed · showing \(at.formatted(date: .omitted, time: .shortened))" }
            else { "Update failed" }
        }
    }

    /// Turns a SwiftUI key press into the name CrossroadsCore expects.
    private func handled(_ press: KeyPress) -> Bool {
        let ctrl = press.modifiers.contains(.control)
        guard let name = keyName(press) else { return false }
        return model.handle(key: name, ctrl: ctrl)
    }
}

/// What the view treats as "now". It is the real clock in the app, and a fixed
/// time when drawing the screenshot, so the picture is the same every time.
private struct NowKey: EnvironmentKey {
    static let defaultValue: Date = .now
}

extension EnvironmentValues {
    var now: Date {
        get { self[NowKey.self] }
        set { self[NowKey.self] = newValue }
    }
}

/// The names keyAction uses: "Up", "Escape", "Tab", "Backtab", "Return", or
/// the character typed.
func keyName(_ press: KeyPress) -> String? {
    switch press.key {
    case .upArrow: return "Up"
    case .downArrow: return "Down"
    case .leftArrow: return "Left"
    case .rightArrow: return "Right"
    case .return: return "Return"
    case .escape: return "Escape"
    case .delete: return "Backspace"
    case .tab: return press.modifiers.contains(.shift) ? "Backtab" : "Tab"
    case .space: return " "
    default:
        let characters = press.characters
        return characters.isEmpty ? nil : characters
    }
}

// ---- Small pieces.

private struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(Palette.urgent))
            .help("\(count) flagged")
    }
}

private struct ModeBadge: View {
    let mode: Mode

    var body: some View {
        Text(mode == .normal ? "NORMAL" : "INSERT")
            .font(.caption2.monospaced().weight(.semibold))
            .foregroundStyle(mode == .normal ? Palette.work : Palette.personal)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill((mode == .normal ? Palette.work : Palette.personal).opacity(0.16))
            )
    }
}

private struct Hint: View {
    let key: String
    let what: String

    init(_ key: String, _ what: String) {
        self.key = key
        self.what = what
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.caption2.monospaced())
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(what).font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }
}

private struct EmptyState: View {
    let searching: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: searching ? "magnifyingglass" : "checkmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(searching ? Color.secondary : Palette.ok)
            Text(searching ? "Nothing matches" : "Nothing needs you right now")
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

private struct RangePicker: View {
    let days: Int

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ranges, id: \.self) { range in
                Text(label(range))
                    .font(.caption.weight(range == days ? .semibold : .regular))
                    .foregroundStyle(range == days ? .white : .secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(range == days ? Palette.personal : Color.primary.opacity(0.06))
                    )
            }
            Spacer()
            Hint("⇥", "range")
        }
    }

    private func label(_ range: Int) -> String {
        range == 0 ? "Today" : "+\(range) days"
    }
}

private struct SectionView: View {
    let section: CrossroadsCore.Section
    let selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accent)
                Text("\(section.items.count)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            if section.columns > 1 {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: section.columns),
                    spacing: 8
                ) {
                    ForEach(section.items, id: \.index) { item in
                        ItemView(item: item, isSelected: item.index == selection)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(section.items, id: \.index) { item in
                        ItemView(item: item, isSelected: item.index == selection)
                    }
                }
            }
            if section.items.isEmpty {
                Text(section.key == .mail ? "No unread mail" : "Nothing today")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
        }
    }

    private var title: String {
        switch section.key {
        case .overlaps: "Clashes"
        case .reminders: "Needs attention"
        case .today: "Today"
        case .mail: "Unread"
        case .events: "Events"
        }
    }

    private var symbol: String {
        switch section.key {
        case .overlaps: "exclamationmark.2"
        case .reminders: "bell.badge"
        case .today: "calendar.day.timeline.left"
        case .mail: "envelope"
        case .events: "calendar"
        }
    }

    private var accent: Color {
        switch section.key {
        case .overlaps: Palette.urgent
        case .reminders: Palette.work
        default: .secondary
        }
    }
}

private struct ItemView: View {
    let item: Item
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            // The colored edge is the tag, and the only place a clash shows
            // both of its colors.
            RoundedRectangle(cornerRadius: 2)
                .fill(stripe)
                .frame(width: 3)
            content
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(wash)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isSelected ? Palette.personal.opacity(0.9) : .clear, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .id(item.index)
    }

    private var stripe: LinearGradient {
        switch item.value {
        case .card(let card):
            Palette.stripe(tag: card.events[0].event.tag, kind: card.kind)
        case .event(let flagged):
            Palette.stripe(tag: flagged.event.tag, kind: flagged.kind)
        case .reminder(let flagged):
            Palette.stripe(tag: flagged.reminder.tag, kind: flagged.kind)
        case .mail(let message):
            LinearGradient(
                colors: [Palette.forSender(message.sender)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// A flagged row gets a wash of its color; everything else stays quiet, so
    /// what matters is what stands out.
    private var wash: Color {
        let base: Color
        switch item.value {
        case .card(let card):
            base = Palette.wash(tag: card.events[0].event.tag, kind: card.kind)
        case .event(let flagged):
            base = flagged.kind == .none
                ? Color.primary.opacity(0.04)
                : Palette.wash(tag: flagged.event.tag, kind: flagged.kind)
        case .reminder(let flagged):
            base = flagged.kind == .none
                ? Color.primary.opacity(0.04)
                : Palette.wash(tag: flagged.reminder.tag, kind: flagged.kind)
        case .mail:
            base = Color.primary.opacity(0.04)
        }
        return isSelected ? base.opacity(0.9) : base
    }

    @ViewBuilder
    private var content: some View {
        switch item.value {
        case .card(let card):
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    ForEach(Array(card.events.enumerated()), id: \.offset) { index, flagged in
                        if index > 0 {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.caption2)
                                .foregroundStyle(Palette.urgent)
                        }
                        TagDot(tag: flagged.event.tag)
                        Text(flagged.event.title).fontWeight(.medium)
                    }
                }
                Text(window(card.start, card.end))
                    .font(.caption)
                    .foregroundStyle(Palette.urgent)
            }
        case .event(let flagged):
            HStack(spacing: 8) {
                TagDot(tag: flagged.event.tag)
                Text(flagged.event.title)
                    .foregroundStyle(flagged.kind == .none ? .secondary : .primary)
                Spacer()
                Text(flagged.event.isAllDay ? "All day" : window(flagged.event.start, flagged.event.end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .reminder(let flagged):
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .font(.caption)
                    .foregroundStyle(Palette.base(flagged.reminder.tag))
                Text(flagged.reminder.title)
                Spacer()
                DueLabel(reminder: flagged.reminder)
            }
        case .mail(let message):
            HStack(spacing: 9) {
                Initial(name: message.sender)
                VStack(alignment: .leading, spacing: 1) {
                    Text(message.subject).fontWeight(.medium).lineLimit(1)
                    Text(message.sender).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    private func window(_ start: Date, _ end: Date) -> String {
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        return "\(from) – \(to)"
    }
}

private struct TagDot: View {
    let tag: Tag

    var body: some View {
        Circle()
            .fill(Palette.base(tag))
            .frame(width: 6, height: 6)
            .help(tag == .work ? "Work" : "Personal")
    }
}

private struct DueLabel: View {
    let reminder: Reminder
    @Environment(\.now) private var now

    var body: some View {
        if let due = reminder.due {
            Text(text(due, late: isLate(due)))
                .font(.caption.weight(isLate(due) ? .semibold : .regular))
                .foregroundStyle(isLate(due) ? Palette.urgent : .secondary)
                .padding(.horizontal, isLate(due) ? 6 : 0)
                .padding(.vertical, isLate(due) ? 2 : 0)
                .background(
                    Capsule().fill(isLate(due) ? Palette.urgent.opacity(0.16) : .clear)
                )
        }
    }

    /// A reminder with a time is late once that time has gone. One with only a
    /// date is late only once the day itself has gone, so a task due today is
    /// not overdue at nine in the morning.
    private func isLate(_ due: Date) -> Bool {
        reminder.hasTime ? due < now : due < Calendar.current.startOfDay(for: now)
    }

    private func text(_ due: Date, late: Bool) -> String {
        guard reminder.hasTime else { return late ? "Overdue" : "Today" }
        let time = due.formatted(date: .omitted, time: .shortened)
        return late ? "Overdue · \(time)" : time
    }
}

private struct Initial: View {
    let name: String

    var body: some View {
        Text(letter)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(Circle().fill(Palette.forSender(name)))
    }

    private var letter: String {
        name.first.map { String($0).uppercased() } ?? "?"
    }
}
