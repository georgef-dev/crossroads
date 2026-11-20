// The settings list, inside the panel. The rows and what each key does come
// from CrossroadsCore.

import SwiftUI

import CrossroadsCore

struct SettingsPanelView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.title3.weight(.semibold))
                Spacer()
                Text("Esc back").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(model.rows, id: \.index) { row in
                        RowView(row: row, isSelected: row.index == model.settingsSelection)
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct RowView: View {
    let row: SettingsRow
    let isSelected: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let note {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(value)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : .clear)
        )
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
        if case .calendar(let calendar) = row.kind { return calendar.source }
        return nil
    }

    private var value: String {
        switch row.kind {
        case .refreshMinutes: row.value == "0" ? "Manual" : "\(row.value) min"
        case .defaultRange: row.value == "0" ? "Today" : "+\(row.value)"
        default: row.value
        }
    }
}
