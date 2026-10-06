import SwiftUI

struct SiteStatsSourcesView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var payload: StatsSourcesPayload?
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        List {
            Section {
                Text("Your own games are always included. Other games stay in their owner's database and are read-only here. Stats and ratings use the databases you select.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let payload {
                    ForEach(payload.sources) { source in
                        Toggle(source.title, isOn: Binding(
                            get: { self.payload?.sources.first(where: { $0.owner == source.owner })?.enabled ?? false },
                            set: { enabled in Task { await updateSource(source.owner, enabled: enabled) } }
                        ))
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
        busy = true
        defer { busy = false }
        do {
            payload = try await PythonAnywhereClient.shared.setStatsSource(owner: owner, enabled: enabled)
            if owner.lowercased() == "kyle" { await auth.refreshMe() }
            auth.statsSourcesChanged()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func updateSharing(_ enabled: Bool) async {
        busy = true
        defer { busy = false }
        do {
            payload = try await PythonAnywhereClient.shared.setStatsSharing(enabled)
            auth.statsSourcesChanged()
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
