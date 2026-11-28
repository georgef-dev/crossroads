// The settings list, inside the panel. The rows and what each key does come
// from CrossroadsCore.

import SwiftUI

import CrossroadsCore

struct SettingsPanelView: View {
    let model: AppModel
    /// A scroll view draws nothing offscreen, so the screenshot stacks the rows.
    var forScreenshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if forScreenshot {
                VStack(spacing: 3) { rows }
                    .padding(14)
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                scrolling
            }
        }
    }

    private func refusedLabel(for row: SettingsRow) -> String? {
        guard row.kind == .shortcut, let refused = model.state.shortcutRefused else { return nil }
        return "\(refused.label) is taken by another app"
    }

    @ViewBuilder
    private var rows: some View {
        ForEach(model.rows, id: \.index) { row in
            RowView(row: row, isSelected: row.index == model.state.settingsSelection)
                .id(row.index)
        }
        if model.state.calendars == nil {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Reading your calendars…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
        }
    }

    /// The selection moves by key, so the list has to follow it: there are
    /// usually more calendars than fit.
    private var scrolling: some View {
        ScrollViewReader { scroller in
            ScrollView {
                VStack(spacing: 3) { rows }
                    .padding(14)
            }
            .onChange(of: model.state.settingsSelection) {
                withAnimation(.easeOut(duration: 0.12)) {
                    scroller.scrollTo(model.state.settingsSelection, anchor: .center)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "slider.horizontal.3")
                .foregroundStyle(Palette.personal)
            Text("Settings").font(.title3.weight(.semibold))
            Spacer()
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("←→").font(.caption2.monospaced())
                    Text("change").font(.caption2)
                }
                HStack(spacing: 4) {
                    Text("esc").font(.caption2.monospaced())
                    Text("back").font(.caption2)
                }
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct RowView: View {
    let row: SettingsRow
    let isSelected: Bool
    var capturing = false
    var refused: String?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(symbolColor)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                if let refused {
                    Text(refused).font(.caption).foregroundStyle(Palette.urgent).lineLimit(1)
                } else if let note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(isSelected ? .secondary : .tertiary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            value
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isSelected ? Palette.personal.opacity(0.16) : Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(isSelected ? Palette.personal.opacity(0.9) : .clear, lineWidth: 1.5)
        )
    }

    @ViewBuilder
    private var value: some View {
        switch row.kind {
        case .calendar:
            // Off, Personal and Work are the whole point of this list, so each
            // one carries its own color.
            Chip(text: row.value.capitalized, color: tagColor, filled: row.value != "off")
        case .shortcut:
            Text(capturing ? "Press keys…" : row.value)
                .font(.callout.monospaced())
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.08)))
        default:
            Text(text)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private var tagColor: Color {
        switch row.value {
        case CalendarSetting.personal.rawValue: Palette.personal
        case CalendarSetting.work.rawValue: Palette.work
        default: .secondary
        }
    }

    private var symbol: String {
        switch row.kind {
        case .refreshMinutes: "arrow.clockwise"
        case .keys: "keyboard"
        case .defaultRange: "calendar.badge.clock"
        case .shortcut: "command"
        case .calendar(let calendar): calendar.kind == .reminders ? "checklist" : "calendar"
        }
    }

    private var symbolColor: Color {
        switch row.kind {
        case .calendar:
            row.value == CalendarSetting.off.rawValue
                ? Color(nsColor: .tertiaryLabelColor)
                : tagColor
        default:
            .secondary
        }
    }

    private var title: String {
        switch row.kind {
        case .refreshMinutes: "Refresh"
        case .keys: "Keys"
        case .defaultRange: "Range on open"
        case .shortcut: "Shortcut"
        case .calendar(let calendar): calendar.name
        }
    }

    private var note: String? {
        guard case .calendar(let calendar) = row.kind else { return nil }
        let what = calendar.kind == .reminders ? "Reminders" : "Calendar"
        return "\(calendar.source) · \(what)"
    }

    private var text: String {
        switch row.kind {
        case .refreshMinutes: row.value == "0" ? "Manual" : "every \(row.value) min"
        case .defaultRange: row.value == "0" ? "Today" : "+\(row.value) days"
        default: row.value
        }
    }
}

private struct Chip: View {
    let text: String
    let color: Color
    let filled: Bool

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(filled ? color : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(filled ? color.opacity(0.18) : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(filled ? color.opacity(0.5) : .clear, lineWidth: 1)
            )
    }
}
