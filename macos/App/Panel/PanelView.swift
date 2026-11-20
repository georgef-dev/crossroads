// The panel: the search field, the range picker, the sections, and the footer.
// Every decision about what to show, and what a key does, comes from
// CrossroadsCore. This file only draws it.

import SwiftUI

import CrossroadsCore

struct PanelView: View {
    @Bindable var model: AppModel
    @FocusState private var searching: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.showingSettings {
                SettingsPanelView(model: model)
            } else {
                header
                Divider()
                list
                Divider()
                footer
            }
        }
        .frame(width: 720, height: 560)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .onKeyPress(phases: .down) { press in
            handled(press) ? .handled : .ignored
        }
        .onAppear { searching = model.mode == .insert }
        .onChange(of: model.mode) { searching = model.mode == .insert }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search events and mail", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($searching)
            RangePicker(days: model.days)
        }
        .padding(16)
    }

    private var list: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(model.sections, id: \.key) { section in
                        SectionView(section: section, selection: model.selection)
                    }
                    if itemCount(model.sections) == 0 {
                        Text("Nothing to show")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(16)
            }
            .onChange(of: model.selection) {
                withAnimation(.easeOut(duration: 0.12)) {
                    scroller.scrollTo(model.selection, anchor: .center)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text(freshness)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if model.settings.keys == .vim {
                Text(model.mode == .normal ? "NORMAL" : "INSERT")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Text("⌃, settings")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var freshness: String {
        switch model.status {
        case .refreshing: "Refreshing…"
        case .fetching: "Fetching…"
        case .updated(let at): "Updated \(at.formatted(date: .omitted, time: .shortened))"
        case .failed(let at):
            if let at { "Last update failed, showing \(at.formatted(date: .omitted, time: .shortened))" }
            else { "Last update failed" }
        }
    }

    /// Turns a SwiftUI key press into the name CrossroadsCore expects.
    private func handled(_ press: KeyPress) -> Bool {
        let ctrl = press.modifiers.contains(.control)
        guard let name = keyName(press) else { return false }
        return model.handle(key: name, ctrl: ctrl)
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

private struct RangePicker: View {
    let days: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ranges, id: \.self) { range in
                Text(label(range))
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(range == days ? Color.accentColor.opacity(0.3) : .clear)
                    )
                    .foregroundStyle(range == days ? .primary : .secondary)
            }
        }
        .help("Tab and Shift+Tab change the range")
    }

    private func label(_ range: Int) -> String {
        range == 0 ? "Today" : "+\(range)"
    }
}

private struct SectionView: View {
    let section: Section
    let selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if section.columns > 1 {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible()), count: section.columns),
                    spacing: 8
                ) {
                    ForEach(section.items, id: \.index) { item in
                        ItemView(item: item, isSelected: item.index == selection)
                    }
                }
            } else {
                ForEach(section.items, id: \.index) { item in
                    ItemView(item: item, isSelected: item.index == selection)
                }
            }
            if section.items.isEmpty {
                Text(section.key == .mail ? "No unread mail" : "Nothing today")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var title: String {
        switch section.key {
        case .overlaps: "Needs attention"
        case .today: "Today"
        case .mail: "Unread"
        case .events: "Events"
        }
    }
}

private struct ItemView: View {
    let item: Item
    let isSelected: Bool

    var body: some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.04))
            )
            .id(item.index)
    }

    @ViewBuilder
    private var content: some View {
        switch item.value {
        case .card(let card):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Palette.color(tag: card.events[0].event.tag, kind: card.kind))
                        .frame(width: 8, height: 8)
                    Text(card.events.map(\.event.title).joined(separator: "  ·  "))
                        .fontWeight(.medium)
                }
                Text(window(card.start, card.end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .event(let flagged):
            HStack(spacing: 8) {
                Circle()
                    .fill(Palette.color(tag: flagged.event.tag, kind: flagged.kind))
                    .frame(width: 8, height: 8)
                Text(flagged.event.title)
                Spacer()
                Text(flagged.event.isAllDay ? "All day" : window(flagged.event.start, flagged.event.end))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .mail(let message):
            VStack(alignment: .leading, spacing: 2) {
                Text(message.subject).fontWeight(.medium).lineLimit(1)
                Text(message.sender).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func window(_ start: Date, _ end: Date) -> String {
        let from = start.formatted(date: .omitted, time: .shortened)
        let to = end.formatted(date: .omitted, time: .shortened)
        return "\(from) – \(to)"
    }
}
