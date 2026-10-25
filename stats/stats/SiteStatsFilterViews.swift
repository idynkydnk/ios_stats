import SwiftUI

struct SiteTimeFrameView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = SiteAuthManager.shared
    var onApply: () -> Void = {}
    @State private var start = Date()
    @State private var end = Date()

    var body: some View {
        Form {
            Section {
                DatePicker("Start day", selection: $start, displayedComponents: .date)
                DatePicker("End day", selection: $end, displayedComponents: .date)
            } footer: {
                Text("Both days are included, regardless of the time games were played. The range applies to standings, player stats, and games.")
            }
            if SiteStatsFilters.day(start) > SiteStatsFilters.day(end) {
                Text("The end day must be on or after the start day.").foregroundStyle(.red)
            }
            Button("Show stats") {
                var filters = auth.statsFilters
                filters.startDay = SiteStatsFilters.day(start)
                filters.endDay = SiteStatsFilters.day(end)
                auth.setStatsFilters(filters)
                dismiss()
                onApply()
            }.disabled(SiteStatsFilters.day(start) > SiteStatsFilters.day(end))
            if auth.statsFilters.hasDates {
                Button("Clear custom time frame") {
                    var filters = auth.statsFilters
                    filters.startDay = ""; filters.endDay = ""
                    auth.setStatsFilters(filters)
                    dismiss()
                    onApply()
                }
            }
        }
        .navigationTitle("Custom time frame")
        .onAppear {
            start = SiteStatsFilters.date(auth.statsFilters.startDay) ?? Date()
            end = SiteStatsFilters.date(auth.statsFilters.endDay) ?? start
        }
    }
}

struct SiteLocationFilterView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = SiteAuthManager.shared
    var onApply: () -> Void = {}
    @State private var locations: [String] = []
    @State private var loading = true
    @State private var error: String?
    var body: some View {
        List {
            Button { choose("", missing: false) } label: {
                row("All locations", selected: auth.statsFilters.location.isEmpty && !auth.statsFilters.missingLocation)
            }
            Button { choose("", missing: true) } label: {
                row("No location yet", selected: auth.statsFilters.missingLocation)
            }
            ForEach(locations, id: \.self) { location in
                Button { choose(location, missing: false) } label: {
                    row(location, selected: !auth.statsFilters.missingLocation && auth.statsFilters.location == location)
                }
            }
            if loading { ProgressView("Loading locations…") }
            if let error { Text(error).foregroundStyle(.red); Button("Retry") { Task { await load() } } }
        }
        .navigationTitle("Location")
        .task(id: auth.browseCacheScope) { await load() }
    }
    private func row(_ title: String, selected: Bool) -> some View {
        HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark") } }
    }
    private func choose(_ location: String, missing: Bool) {
        var filters = auth.statsFilters
        filters.location = location; filters.missingLocation = missing
        auth.setStatsFilters(filters)
        dismiss()
        onApply()
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do {
            let result = try await PythonAnywhereClient.shared.years()
            try Task.checkCancellation()
            guard let values = result.locations else {
                error = "Location selection needs the latest server update."
                return
            }
            locations = values
        } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

struct SiteStatsFilterSummary: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    var body: some View {
        if auth.statsFilters.isActive {
            VStack(alignment: .leading, spacing: 6) {
                Text(auth.statsFilters.summary).font(.subheadline)
                HStack {
                    NavigationLink("Dates") { SiteTimeFrameView() }
                    NavigationLink("Location") { SiteLocationFilterView() }
                    Button("Clear filters") { auth.setStatsFilters(SiteStatsFilters()) }
                }.font(.caption)
            }.padding(.horizontal)
        }
    }
}
