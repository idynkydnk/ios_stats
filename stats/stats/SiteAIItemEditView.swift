import SwiftUI

struct SiteAIItemControls: View {
    var kind: String
    var shareId: String
    var onChanged: () -> Void
    var onDeleted: () -> Void
    @State private var editing = false
    @State private var confirmingDelete = false
    @State private var deleting = false
    @State private var error: String?

    var body: some View {
        Menu {
            Button("Edit \(kind)", systemImage: "pencil") { editing = true }
            Button("Delete \(kind)", systemImage: "trash", role: .destructive) { confirmingDelete = true }
        } label: {
            if deleting { ProgressView("Deleting…") }
            else { Label("Manage", systemImage: "ellipsis.circle") }
        }
        .disabled(deleting)
        .confirmationDialog("Delete this \(kind)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete \(kind)", role: .destructive) {
                Task { await delete() }
            }
        } message: {
            Text("This permanently removes the \(kind) and its shared page.")
        }
        .alert("Couldn't delete \(kind)", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .sheet(isPresented: $editing) {
            NavigationStack {
                SiteAIItemEditView(kind: kind, shareId: shareId, onChanged: onChanged)
            }
        }
    }

    @MainActor private func delete() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        do {
            try await PythonAnywhereClient.shared.deleteAIItem(kind: kind, shareId: shareId)
            onDeleted()
        } catch { self.error = error.localizedDescription }
    }
}

struct SiteAIItemEditView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.siteAppearance) private var appearance
    var kind: String
    var shareId: String
    var onChanged: () -> Void
    @State private var item: AIItemEditPayload?
    @State private var busy = false
    @State private var progress = "Saving changes…"
    @State private var error: String?
    @State private var message: String?
    @State private var remakeSummary: Bool?

    var body: some View {
        List {
            if let error { Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red) }
            if let message { Label(message, systemImage: "checkmark.circle").foregroundStyle(appearance.accent) }
            if busy { ProgressView(progress) }
            if item != nil {
                SiteListSection(kind == "recap" ? "Recap text" : "Flyer details") {
                    field("Title", \.title)
                    if kind == "recap" {
                        field("Summary", \.summary, multiline: true)
                    } else {
                        field("Date (YYYY-MM-DD)", \.eventDate)
                        field("Time (HH:MM)", \.eventTime)
                        field("Location", \.location)
                        field("Picture details", \.imageDetails, multiline: true)
                        Text("Saving updates the event details. Remake the picture to put changed details into the flyer image.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Button("Save changes") { Task { await save() } }
                }
                if kind == "recap" {
                    SiteListSection("Remake summary") {
                        field("Style instructions", \.customPrompt, multiline: true)
                        Text("Leave blank to use the standard recap style. Remaking replaces the current summary.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Remake summary") { remakeSummary = true }
                    }
                }
                SiteListSection("Remake picture") {
                    field("Picture instructions", \.scenePrompt, multiline: true)
                    Text("Edit the saved instructions, or clear them to build a new prompt from the saved games or event details. Remaking replaces the current picture.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Remake picture") { remakeSummary = false }
                }
            } else if !busy {
                if error == nil { ProgressView("Loading…") }
                else { Button("Try again") { Task { await load() } } }
            }
        }
        .disabled(busy)
        .scrollContentBackground(.hidden)
        .background(appearance.background)
        .tint(appearance.accent)
        .navigationTitle("Edit \(kind)")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .interactiveDismissDisabled(busy)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
        .task { await load() }
        .confirmationDialog("Remake \(remakeSummary == true ? "summary" : "picture")?", isPresented: Binding(
            get: { remakeSummary != nil }, set: { if !$0 { remakeSummary = nil } }
        ), titleVisibility: .visible) {
            let summary = remakeSummary == true
            Button("Save changes and remake") { Task { await save(remake: summary) } }
        } message: {
            Text("Your text and details will be saved first. The current \(remakeSummary == true ? "summary" : "picture") will then be replaced. This may take a few minutes.")
        }
    }

    private func field(_ title: String, _ key: WritableKeyPath<AIItemEditPayload, String>, multiline: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold))
            TextField(title, text: Binding(get: { item?[keyPath: key] ?? "" }, set: { item?[keyPath: key] = $0 }), axis: multiline ? .vertical : .horizontal)
                .lineLimit(multiline ? 5...16 : 1...1)
                .textInputAutocapitalization(.sentences)
                .accessibilityLabel(title)
        }
    }

    @MainActor private func load() async {
        do {
            item = try await PythonAnywhereClient.shared.aiItemDetails(kind: kind, shareId: shareId)
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func save(remake: Bool? = nil) async {
        guard !busy, let item else { return }
        busy = true
        progress = "Saving changes…"
        error = nil
        message = nil
        defer { busy = false }
        let fields = kind == "recap" ? ["title": item.title, "summary": item.summary] : [
            "title": item.title, "event_date": item.eventDate, "event_time": item.eventTime,
            "location": item.location, "image_details": item.imageDetails
        ]
        do {
            try await PythonAnywhereClient.shared.saveAIItem(kind: kind, shareId: shareId, fields: fields)
            onChanged()
            if let remake {
                progress = remake ? "Remaking summary…" : "Remaking picture…"
                message = try await PythonAnywhereClient.shared.remakeAIItem(kind: kind, shareId: shareId, summary: remake,
                    prompt: remake ? item.customPrompt : item.scenePrompt)
                onChanged()
                await load()
            } else { message = "Changes saved." }
        } catch { self.error = error.localizedDescription }
    }
}
