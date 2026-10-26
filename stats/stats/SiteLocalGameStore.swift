import Foundation
import Combine

@MainActor
final class SiteLocalGameStore: ObservableObject {
    static let shared = SiteLocalGameStore()
    @Published private(set) var games: [SiteLocalGame] = []
    @Published private(set) var syncing = false
    @Published private(set) var message: String?
    private var ledger: SiteLocalGameLedger?
    private var worker: Task<Void, Never>?
    private var workerID: UUID?
    private var owner: String?

    init(url: URL? = nil) {
        let file = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StatsLocal-v1/games.json")
        do { ledger = try SiteLocalGameLedger(url: file) }
        catch { message = "Couldn’t read games saved on this phone. Your saved file has been kept. \(error.localizedDescription)" }
    }
    var pending: [SiteLocalGame] { games.filter { $0.serverID == nil } }
    func selectAccount(_ name: String?) {
        guard owner != name else { return }
        worker?.cancel()
        worker = nil
        workerID = nil
        syncing = false
        owner = name
        publish()
    }
    private func publish() { games = ledger?.games.filter { $0.owner == owner } ?? [] }

    func save(kind: String, fields: [String: Any]) throws {
        guard let name = SiteAuthManager.shared.username, SiteAuthManager.shared.isLoggedIn else { throw SiteAPIError.unauthorized }
        selectAccount(name)
        guard let ledger else { throw SiteAPIError.message(message ?? "Couldn’t open saved games on this phone.") }
        try ledger.add(owner: name, kind: kind, fields: fields)
        publish()
        startSync()
    }
    func removeAccount(_ name: String) throws {
        guard let ledger else { return }
        try ledger.replace(ledger.games.filter { $0.owner != name })
        selectAccount(nil)
    }
    func retry() {
        guard let ledger else { return }
        do {
            try ledger.replace(ledger.games.map { game in
                var game = game
                if game.owner == owner { game.needsAttention = false; game.failure = nil }
                return game
            })
            message = nil
            publish()
            startSync()
        } catch { message = "Couldn’t update saved games. \(error.localizedDescription)" }
    }
    func startSync() {
        guard worker == nil, !pending.isEmpty, NetworkMonitor.shared.isConnected,
              SiteAuthManager.shared.sessionReady, !SiteAuthManager.shared.isPreviewing else { return }
        let account = owner
        let runID = UUID()
        workerID = runID
        worker = Task {
            await run(account: account)
            // A switched account may already have started a different worker.
            if workerID == runID { worker = nil; workerID = nil; syncing = false }
        }
    }
    private func run(account: String?) async {
        let token = SiteAuthManager.shared.token
        var delay = 2
        var capabilityChecked = false
        var changed = false
        func refreshSnapshots() {
            guard changed else { return }
            SiteBrowseCache.shared.markStale()
            SiteBrowseCache.playerDetails.markStale()
            SiteBrowseCache.navigation.markStale()
            SiteBrowseCache.playerSuggestions.markStale()
            changed = false
        }
        defer { refreshSnapshots() }
        while !Task.isCancelled, owner == account, SiteAuthManager.shared.token == token,
              NetworkMonitor.shared.isConnected, let ledger {
            guard let item = pending.first(where: { !$0.needsAttention }) else { return }
            syncing = true
            do {
                if !capabilityChecked {
                    try await PythonAnywhereClient.shared.requireLocalGameSync()
                    capabilityChecked = true
                }
                try Task.checkCancellation()
                guard owner == account, SiteAuthManager.shared.token == token else { return }
                let receipt = try await PythonAnywhereClient.shared.syncLocalGame(item)
                // Persist even if the active account changed after the POST; the
                // receipt belongs to the item and can never move to another account.
                try ledger.acknowledge(item.id, serverID: receipt)
                changed = true
                if owner == account { publish(); message = nil }
                delay = 2
                // Keep existing values readable; coalesce a run of saves into one refresh.
                if !pending.contains(where: { !$0.needsAttention }) {
                    refreshSnapshots()
                }
            } catch {
                guard !Task.isCancelled, owner == account else { return }
                syncing = false
                refreshSnapshots()
                let permanent: Bool
                switch error {
                case SiteAPIError.http(let code, _): permanent = [400, 403, 409, 422].contains(code)
                case SiteAPIError.unauthorized: permanent = true
                default: permanent = false
                }
                var next = ledger.games
                if let index = next.firstIndex(where: { $0.id == item.id }) {
                    next[index].failure = error.localizedDescription
                    next[index].needsAttention = permanent
                    do { try ledger.replace(next) }
                    catch { message = "Your game is saved, but its sync status couldn’t be stored. Retrying is safe."; return }
                }
                publish()
                message = error.localizedDescription
                if permanent { continue }
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                delay = min(delay * 2, 60)
            }
        }
    }
}
