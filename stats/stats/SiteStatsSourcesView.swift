import SwiftUI

struct SiteStatsSourcesView: View {
    var onApply: () -> Void = {}
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var payload: StatsSourcesPayload?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        List {
            Section {
                Text(payload?.canSelectOnly == true
                     ? "Tap a name to show only that account’s stats. Use the switches to combine accounts, or turn off My stats to leave yours out. Other accounts’ games are read-only here."
                     : "Your own games are always included. Other games stay in their owner's database and are read-only here. Stats and ratings use the databases you select.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let payload {
                    ForEach(payload.sources) { source in
                        let selection = Binding(
                            get: { self.payload?.sources.first(where: { $0.owner == source.owner })?.enabled ?? false },
                            set: { enabled in Task { await updateSource(source.owner, enabled: enabled) } }
                        )
                        if payload.canSelectOnly == true && source.owner.lowercased() != "kyle" {
                            HStack {
                                Button { Task { await selectOnly(source.owner) } } label: {
                                    Text(source.title)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.borderless)
                                .accessibilityHint("Show only this account’s stats")
                                Toggle("Include \(source.title)", isOn: selection)
                                    .labelsHidden()
                            }
                        } else {
                            Toggle(source.title, isOn: selection)
                        }
                    }
                }
            }
            if payload?.isPrivate == true {
                Section("Sharing") {
                    Toggle("Let the existing group include my stats", isOn: Binding(
                        get: { payload?.shareStats ?? false },
                        set: { enabled in Task { await updateSharing(enabled) } }
                    ))
                    Text("New accounts can include KT Stats only. Kyle can include your stats as the administrator. Turning sharing off removes access for other users.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .disabled(busy)
        .navigationTitle("Stats to include")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        do {
            payload = try await PythonAnywhereClient.shared.statsSources()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func updateSource(_ owner: String, enabled: Bool) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            payload = try await PythonAnywhereClient.shared.setStatsSource(owner: owner, enabled: enabled)
            if owner.lowercased() == "kyle" { await auth.refreshMe() }
            auth.statsSourcesChanged()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func selectOnly(_ owner: String) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            payload = try await PythonAnywhereClient.shared.selectOnlyStatsSource(owner: owner)
            auth.browseSelectedStats = true
            auth.statsSourcesChanged()
            error = nil
            onApply()
        } catch { self.error = error.localizedDescription }
    }

    private func updateSharing(_ enabled: Bool) async {
        busy = true
        defer { busy = false }
        do {
            payload = try await PythonAnywhereClient.shared.setStatsSharing(enabled)
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
