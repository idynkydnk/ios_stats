import SwiftUI

enum SiteAddAccent {
    static let orange = Color(red: 1, green: 0.45, blue: 0.3)
}

func siteNowString() -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return df.string(from: Date())
}

func sitePromote(_ names: [String], in list: inout [String]) {
    var front: [String] = []
    var seen = Set<String>()
    for raw in names {
        let n = raw.trimmingCharacters(in: .whitespaces)
        let key = n.lowercased()
        guard !n.isEmpty, seen.insert(key).inserted else { continue }
        front.append(n)
    }
    let rest = list.filter { name in
        !front.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }
    list = front + rest
}

func siteFilterPlayers(_ all: [String], query: String, excluding: [String], limit: Int = 12) -> [String] {
    let taken = Set(excluding.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty })
    let available = all.filter { !taken.contains($0.lowercased()) }
    let q = query.trimmingCharacters(in: .whitespaces).lowercased()
    if q.isEmpty { return Array(available.prefix(limit)) }
    return Array(available.filter { $0.lowercased().contains(q) }.prefix(limit))
}

func siteLoserScores(winner: Int?) -> [Int] {
    let w = winner ?? 21
    let start = max(0, w - 2)
    return Array(stride(from: start, through: 0, by: -1))
}

func siteIsToday(_ date: Date) -> Bool {
    Calendar.current.isDateInToday(date)
}

struct SiteAddTextRow<Field: Hashable>: View {
    var label: String
    @Binding var text: String
    var field: Field
    var focus: FocusState<Field?>.Binding
    var keyboard: UIKeyboardType = .default
    var submit: SubmitLabel = .next
    var onSubmit: () -> Void
    var onFocus: () -> Void = {}

    var body: some View {
        let isFocused = focus.wrappedValue == field
        ZStack(alignment: .trailing) {
            TextField(label, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .keyboardType(keyboard)
                .submitLabel(submit)
                .focused(focus, equals: field)
                .onSubmit(onSubmit)
                .onChange(of: focus.wrappedValue) { _, new in
                    if new == field { onFocus() }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .padding(.trailing, 28)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? SiteAddAccent.orange : Color.clear, lineWidth: 2)
                )
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
        }
        .id(field)
    }
}

struct SiteAddScoreRow<Field: Hashable>: View {
    var label: String
    @Binding var value: Int?
    var field: Field
    var focus: FocusState<Field?>.Binding
    var submit: SubmitLabel = .next
    var onSubmit: () -> Void
    var onFocus: () -> Void = {}

    var body: some View {
        let isFocused = focus.wrappedValue == field
        let scoreString = Binding(
            get: { value.map { "\($0)" } ?? "" },
            set: { new in
                let digits = new.filter(\.isNumber)
                if digits.isEmpty { value = nil }
                else if let n = Int(digits), n >= 0, n <= 99 { value = n }
            }
        )
        ZStack(alignment: .trailing) {
            TextField(label, text: scoreString)
                .keyboardType(.numberPad)
                .submitLabel(submit)
                .focused(focus, equals: field)
                .onSubmit(onSubmit)
                .onChange(of: focus.wrappedValue) { _, new in
                    if new == field { onFocus() }
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .padding(.trailing, 28)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill)))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? SiteAddAccent.orange : Color.clear, lineWidth: 2)
                )
            if value != nil {
                Button { value = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10)
            }
        }
        .id(field)
    }
}

struct SiteAddSuggestionList: View {
    var names: [String]
    var onPick: (String) -> Void

    var body: some View {
        if !names.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    Button {
                        onPick(name)
                    } label: {
                        Text(name)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < names.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct SiteAddScoreChips: View {
    var scores: [Int]
    var selected: Int?
    var onPick: (Int) -> Void

    var body: some View {
        if !scores.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(scores, id: \.self) { s in
                        Button {
                            onPick(s)
                        } label: {
                            Text("\(s)")
                                .font(.headline)
                                .foregroundStyle(selected == s ? Color.black : Color.primary)
                                .frame(minWidth: 44)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selected == s ? SiteAddAccent.orange : Color(.secondarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct SiteAddBanner: View {
    var text: String
    var isError: Bool = false

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isError ? Color.red : Color.green)
            .frame(maxWidth: .infinity)
            .padding(10)
            .background((isError ? Color.red : Color.green).opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct SiteAddActionButton: View {
    var title: String
    var filled: Bool = false
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(filled ? SiteAddAccent.orange : Color(.secondarySystemFill))
                .foregroundStyle(filled ? Color.black : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}
