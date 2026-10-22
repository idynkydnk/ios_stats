import SwiftUI

struct SiteAIConsent: Codable, Equatable {
    var version: String
    var granted: Bool
    var disclosure: String
    var providers: [String]
}

struct SiteBlockedUsers: Decodable {
    struct User: Decodable, Identifiable {
        var username: String
        var id: String { username }
    }
    var users: [User]
}

enum SitePolicyLinks {
    static let privacy = PythonAnywhereClient.shared.baseURL.appendingPathComponent("privacy")
    static let support = PythonAnywhereClient.shared.baseURL.appendingPathComponent("support")
    static let community = PythonAnywhereClient.shared.baseURL.appendingPathComponent("community-guidelines")
}

/// The disclosure is fetched from the server so a changed policy requires fresh
/// permission. Granting it does not submit the user's content or start a job.
struct SiteAIConsentControl: View {
    var alwaysExpanded = false
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var consent: SiteAIConsent?
    @State private var busy = false
    @State private var error: String?
    @State private var declined = false
    @State private var confirmingWithdrawal = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI and content safety sharing", systemImage: "hand.raised")
                .font(.headline)
            if let consent {
                if !consent.granted || alwaysExpanded {
                    Text(consent.disclosure).font(.subheadline)
                    Text("Only share information and photos you have permission to use. You can keep browsing and recording scores without enabling these features.")
                        .font(.caption).foregroundStyle(.secondary)
                    Link("Read privacy policy", destination: SitePolicyLinks.privacy)
                }
                if consent.granted {
                    Label("Sharing allowed", systemImage: "checkmark.shield")
                        .font(.subheadline).foregroundStyle(.secondary)
                    if alwaysExpanded {
                        Button("Withdraw permission", role: .destructive) { confirmingWithdrawal = true }
                    } else {
                        NavigationLink("Manage permission") { SitePrivacySafetyView() }
                    }
                } else if declined {
                    Text("Sharing is off. Photos, AI generation, and shared-content editing will wait for your permission.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Review permission") { declined = false }
                } else {
                    Button("Allow sharing with " + consent.providers.joined(separator: " and ")) {
                        Task { await save(granted: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Not now") { declined = true }
                }
            } else if !busy && error == nil {
                ProgressView("Loading privacy information…")
            }
            if busy { ProgressView("Updating…") }
            if let error {
                Text(error).foregroundStyle(.red).font(.subheadline)
                if consent == nil { Button("Try again") { Task { await load() } } }
            }
        }
        .disabled(busy)
        .task(id: auth.token) { await load() }
        .confirmationDialog("Withdraw AI and content safety permission?", isPresented: $confirmingWithdrawal,
                            titleVisibility: .visible) {
            Button("Withdraw permission", role: .destructive) { Task { await save(granted: false) } }
        } message: {
            Text("This stops future sharing for these features. Information already sent cannot be recalled. Existing content remains until you delete it or your account.")
        }
    }

    @MainActor private func load() async {
        let owner = auth.token
        consent = nil
        error = nil
        busy = true
        declined = false
        defer { busy = false }
        do {
            let response = try await PythonAnywhereClient.shared.aiConsent()
            guard owner == auth.token, !Task.isCancelled else { return }
            consent = response
        } catch {
            guard owner == auth.token, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    @MainActor private func save(granted: Bool) async {
        guard let consent else { return }
        let owner = auth.token
        busy = true
        error = nil
        defer { busy = false }
        do {
            let response = try await PythonAnywhereClient.shared.setAIConsent(version: consent.version, granted: granted)
            guard owner == auth.token else { return }
            self.consent = response
            declined = !granted
        } catch {
            guard owner == auth.token else { return }
            self.error = error.localizedDescription
        }
    }
}

struct SitePrivacySafetyView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    var body: some View {
        List {
            Section("Information and help") {
                Link("Privacy policy", destination: SitePolicyLinks.privacy)
                Link("Support", destination: SitePolicyLinks.support)
                Link("Community guidelines", destination: SitePolicyLinks.community)
            }
            if auth.isLoggedIn {
                Section { SiteAIConsentControl(alwaysExpanded: true) }
                Section {
                    NavigationLink("Blocked users") { SiteBlockedUsersView() }
                } footer: {
                    Text("Report an offensive recap or flyer from its Safety menu. Blocking hides that author's shared content from your account.")
                }
            }
        }
        .navigationTitle("Privacy and safety")
    }
}

struct SiteBlockedUsersView: View {
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var users: [SiteBlockedUsers.User] = []
    @State private var busy = false
    @State private var loaded = false
    @State private var error: String?
    @State private var pendingUnblock: SiteBlockedUsers.User?

    var body: some View {
        List {
            if busy { ProgressView("Updating blocked users…") }
            if let error { Text(error).foregroundStyle(.red) }
            if loaded && users.isEmpty { Text("You haven't blocked anyone.").foregroundStyle(.secondary) }
            ForEach(users) { user in
                HStack {
                    Text(user.username)
                    Spacer()
                    Button("Unblock") { pendingUnblock = user }
                }
            }
        }
        .disabled(busy)
        .navigationTitle("Blocked users")
        .task(id: auth.token) { await load() }
        .refreshable { await load() }
        .confirmationDialog("Unblock this user?", isPresented: Binding(
            get: { pendingUnblock != nil }, set: { if !$0 { pendingUnblock = nil } }
        ), titleVisibility: .visible) {
            if let user = pendingUnblock {
                Button("Unblock \(user.username)") { Task { await unblock(user) } }
            }
        } message: { Text("Their shared content can appear again.") }
    }

    @MainActor private func load() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            users = try await PythonAnywhereClient.shared.blockedUsers().users
            loaded = true
        } catch { self.error = error.localizedDescription }
    }

    @MainActor private func unblock(_ user: SiteBlockedUsers.User) async {
        busy = true
        error = nil
        defer { busy = false }
        do { users = try await PythonAnywhereClient.shared.setBlockedUser(user.username, blocked: false).users }
        catch { self.error = error.localizedDescription }
    }
}

struct SiteContentSafetyControls: View {
    var kind: String
    var shareId: String
    var username: String?
    var onBlocked: () -> Void = {}
    @ObservedObject private var auth = SiteAuthManager.shared
    @State private var reporting = false
    @State private var confirmingBlock = false
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        Menu {
            Button("Report content", systemImage: "flag") { reporting = true }
            if let username, !username.isEmpty, username.lowercased() != auth.username?.lowercased() {
                if auth.isLoggedIn {
                    Button("Block this author", systemImage: "person.slash", role: .destructive) { confirmingBlock = true }
                } else {
                    NavigationLink("Sign in to block this author") { LoginView() }
                }
            }
            Link("Community guidelines", destination: SitePolicyLinks.community)
            Link("Contact support", destination: SitePolicyLinks.support)
        } label: {
            if busy { ProgressView() }
            else { Label("Safety", systemImage: "flag") }
        }
        .disabled(busy)
        .sheet(isPresented: $reporting) {
            NavigationStack { SiteReportContentView(kind: kind, shareId: shareId) }
        }
        .confirmationDialog("Block this author?", isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block author", role: .destructive) { Task { await block() } }
        } message: {
            Text("Their shared content will be hidden from your account. You can unblock them in More → Privacy and safety → Blocked users.")
        }
        .alert("Couldn't block author", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    @MainActor private func block() async {
        guard let username else { return }
        busy = true
        defer { busy = false }
        do {
            _ = try await PythonAnywhereClient.shared.setBlockedUser(username, blocked: true)
            onBlocked()
        } catch { self.error = error.localizedDescription }
    }
}

private struct SiteReportContentView: View {
    @Environment(\.dismiss) private var dismiss
    var kind: String
    var shareId: String
    @State private var category = "Harassment or bullying"
    @State private var details = ""
    @State private var busy = false
    @State private var sent = false
    @State private var error: String?
    private let categories = ["Harassment or bullying", "Sexual or violent content", "Photo or privacy concern", "Copyright or impersonation", "Other"]

    var body: some View {
        Form {
            if sent {
                Section {
                    Label("Report sent", systemImage: "checkmark.circle")
                    Text("Thank you. The site administrator can review this content and take action.")
                    Button("Done") { dismiss() }
                }
            } else {
                Section("What is wrong?") {
                    Picker("Reason", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                    TextField("Additional details (optional)", text: $details, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: details) { _, value in if value.count > 1500 { details = String(value.prefix(1500)) } }
                }
                Section {
                    Text("Your report identifies this \(kind) and includes your reason and any details. It is sent to the site administrator, not published on the shared page.")
                        .font(.footnote)
                    Link("Privacy policy", destination: SitePolicyLinks.privacy)
                    Link("Contact support", destination: SitePolicyLinks.support)
                    if let error { Text(error).foregroundStyle(.red) }
                    Button("Send report") { Task { await send() } }.disabled(busy)
                    if busy { ProgressView("Sending…") }
                }
            }
        }
        .navigationTitle("Report \(kind)")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(busy) }
        }
        .interactiveDismissDisabled(busy)
    }

    @MainActor private func send() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let reason = details.trimmingCharacters(in: .whitespacesAndNewlines)
            try await PythonAnywhereClient.shared.reportContent(kind: kind, shareId: shareId,
                reason: reason.isEmpty ? category : category + ": " + reason)
            sent = true
        } catch { self.error = error.localizedDescription }
    }
}
