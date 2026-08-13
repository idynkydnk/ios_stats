import SwiftUI

struct DatabaseListItem: Hashable {
    let id: String
    let displayName: String
}

/// Databases tab: explanation, your database (upload / create code), get edit access (enter code), and list of all databases.
struct BrowseDatabasesView: View {
    /// When set, tapping a database calls this and switches to main Stats tab with that database's data.
    var onSelectDatabase: ((_ dbId: String, _ displayName: String) -> Void)? = nil

    @ObservedObject private var dbOwner = DatabaseOwnerManager.shared
    @ObservedObject private var auth = AuthManager.shared
    @State private var databases: [DatabaseListItem] = []
    @State private var isSigningIn = false
    @State private var signInError: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var enteredCode = ""
    @State private var codeError: String?
    @State private var createdCode: String?
    @State private var isCreatingCode = false
    @State private var isSubmittingCode = false
    @State private var showDatabaseNameSheet = false
    @State private var databaseNameInput = ""
    @State private var uploadError: String?
    @State private var isUploading = false
    @State private var showRenameSheet = false
    @State private var renameInput = ""
    @State private var renameError: String?
    @State private var isRenaming = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var showAdminActivity = false
    @State private var showAdminPlayers = false
    @State private var databaseToRename: DatabaseListItem?
    @State private var databaseToDelete: DatabaseListItem?
    @State private var showRecalcStatsConfirm = false
    @State private var isRecalculatingStats = false
    @State private var recalcStatsError: String?
    @State private var showImport2026Confirm = false
    @State private var isImporting2026 = false
    @State private var import2026Progress = ""
    @State private var import2026Error: String?
    @State private var myDatabaseIsUnnamedInCloud = false

    /// List for display: my database first (if any), then others (excluding my db from the rest).
    private var displayedDatabases: [DatabaseListItem] {
        var list = databases
        if let myId = dbOwner.myDbId {
            list = list.filter { $0.id != myId }
        }
        if let myId = dbOwner.myDbId {
            return [DatabaseListItem(id: myId, displayName: dbOwner.myDatabaseDisplayName)] + list
        }
        return list
    }

    private var hasMyDatabase: Bool { dbOwner.hasMyDatabase }

    private static let explanationText = "All stats are stored in the cloud. Create your database, then add games from the Stats or Games tab. Tap any database to view its stats; use a share code to let others add or edit your database."

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.1, blue: 0.16),
                        Color(red: 0.1, green: 0.14, blue: 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(Color(red: 1, green: 0.45, blue: 0.3))
                } else if let err = errorMessage {
                    VStack(spacing: 12) {
                        Text(err)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                } else {
                    List {
                        if myDatabaseIsUnnamedInCloud {
                            Section {
                                HStack {
                                    Text("Your database is listed as \"Unnamed\" in the cloud. Rename it (e.g. \"KT\") so others can find it.")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Spacer()
                                    Button("Rename") {
                                        guard let myId = dbOwner.myDbId else { return }
                                        databaseToRename = DatabaseListItem(id: myId, displayName: dbOwner.myDatabaseDisplayName)
                                        renameInput = dbOwner.myDatabaseDisplayName
                                        renameError = nil
                                        showRenameSheet = true
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(Color(red: 1, green: 0.45, blue: 0.3))
                                }
                                .listRowBackground(Color.orange.opacity(0.2))
                            }
                        }
                        Section {
                            if displayedDatabases.isEmpty {
                                Text("No databases yet")
                                    .font(.system(size: 15, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.6))
                            } else {
                                ForEach(displayedDatabases, id: \.id) { db in
                                    let isMyDb = db.id == dbOwner.myDbId
                                    Group {
                                        if onSelectDatabase != nil {
                                            Button {
                                                onSelectDatabase?(db.id, db.displayName)
                                            } label: {
                                                databaseRow(db: db, isMyDatabase: isMyDb)
                                            }
                                        } else {
                                            NavigationLink(value: db) {
                                                databaseRow(db: db, isMyDatabase: isMyDb)
                                            }
                                        }
                                    }
                                    .contextMenu {
                                        if isMyDb || dbOwner.isAdmin {
                                            Button {
                                                databaseToRename = isMyDb ? DatabaseListItem(id: dbOwner.myDbId!, displayName: dbOwner.myDatabaseDisplayName) : db
                                                renameInput = databaseToRename!.displayName
                                                renameError = nil
                                                showRenameSheet = true
                                            } label: { Label("Rename", systemImage: "pencil") }
                                            Button(role: .destructive) {
                                                databaseToDelete = isMyDb ? nil : db
                                                showDeleteConfirm = true
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if isMyDb || dbOwner.isAdmin {
                                            Button(role: .destructive) {
                                                databaseToDelete = isMyDb ? nil : db
                                                showDeleteConfirm = true
                                            } label: { Label("Delete", systemImage: "trash") }
                                        }
                                    }
                                }
                            }
                        } header: {
                            Text("View databases")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                        .listRowSeparatorTint(.white.opacity(0.15))

                        if auth.isSignedIn && dbOwner.isAdmin {
                            Section {
                                Button {
                                    showAdminActivity = true
                                } label: {
                                    Label("Activity log", systemImage: "list.bullet.rectangle")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                }
                                .buttonStyle(.plain)
                                Button {
                                    showAdminPlayers = true
                                } label: {
                                    Label("Manage players", systemImage: "person.2.fill")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                }
                                .buttonStyle(.plain)
                                Button {
                                    guard let dbId = dbOwner.myDbId else { return }
                                    recalcStatsError = nil
                                    isRecalculatingStats = true
                                    cloud.recomputeStatsNow(dbId: dbId) { result in
                                        isRecalculatingStats = false
                                        switch result {
                                        case .success:
                                            showRecalcStatsConfirm = true
                                        case .failure(let err):
                                            recalcStatsError = err.localizedDescription
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Label("Recalculate stats from all games", systemImage: "chart.bar.doc.plaintext")
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                        if isRecalculatingStats {
                                            Spacer()
                                            ProgressView()
                                                .scaleEffect(0.9)
                                                .tint(Color(red: 1, green: 0.45, blue: 0.3))
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(dbOwner.myDbId == nil || isRecalculatingStats)
                                if let err = recalcStatsError {
                                    Text(err)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                                }
                            } header: {
                                Text("Admin")
                                    .foregroundStyle(.white.opacity(0.7))
                            } footer: {
                                Text("Rename/delete databases from the list above; view activity and manage players per database.")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                            .listRowSeparatorTint(.white.opacity(0.15))
                        }

                        Section {
                            Text(Self.explanationText)
                                .font(.system(size: 14, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                        .listRowSeparatorTint(.white.opacity(0.15))

                        Section {
                            if !hasMyDatabase {
                                Button {
                                    uploadError = nil
                                    showDatabaseNameSheet = true
                                } label: {
                                    HStack {
                                        Label("Create your database", systemImage: "cloud.fill")
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                        if isUploading {
                                            Spacer()
                                            ProgressView()
                                                .scaleEffect(0.9)
                                                .tint(Color(red: 1, green: 0.45, blue: 0.3))
                                        }
                                    }
                                }
                                .disabled(isUploading)
                                if let err = uploadError {
                                    Text(err)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                                }
                            } else {
                                if onSelectDatabase != nil, let myId = dbOwner.myDbId {
                                    Button {
                                        onSelectDatabase?(myId, dbOwner.myDatabaseDisplayName)
                                    } label: {
                                        databaseRow(db: DatabaseListItem(id: myId, displayName: dbOwner.myDatabaseDisplayName), isMyDatabase: true)
                                    }
                                    .contextMenu {
                                        Button {
                                            if let myId = dbOwner.myDbId {
                                                databaseToRename = DatabaseListItem(id: myId, displayName: dbOwner.myDatabaseDisplayName)
                                            }
                                            renameInput = dbOwner.myDatabaseDisplayName
                                            renameError = nil
                                            showRenameSheet = true
                                        } label: { Label("Rename", systemImage: "pencil") }
                                        Button(role: .destructive) {
                                            databaseToDelete = nil
                                            showDeleteConfirm = true
                                        } label: { Label("Delete", systemImage: "trash") }
                                    }
                                }
                                Button {
                                    isCreatingCode = true
                                    dbOwner.createCode { result in
                                        isCreatingCode = false
                                        switch result {
                                        case .success(let code): createdCode = code
                                        case .failure: break
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Label("Create code to share", systemImage: "plus.circle")
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                        if isCreatingCode {
                                            Spacer()
                                            ProgressView()
                                                .scaleEffect(0.9)
                                                .tint(Color(red: 1, green: 0.45, blue: 0.3))
                                        }
                                    }
                                }
                                .disabled(isCreatingCode)
                            }
                        } header: {
                            Text("Your database")
                                .foregroundStyle(.white.opacity(0.7))
                        } footer: {
                            if !hasMyDatabase {
                                Text("Create a named cloud database. Add games from the Stats or Games tab.")
                                    .foregroundStyle(.white.opacity(0.5))
                            } else {
                                Text("Share your code with others; anyone who enters it can add or edit games in your database.")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                        .listRowSeparatorTint(.white.opacity(0.15))

                        Section {
                            TextField("Enter share code", text: $enteredCode)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .foregroundStyle(.white)
                            if let err = codeError {
                                Text(err)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                            }
                            Button {
                                codeError = nil
                                isSubmittingCode = true
                                dbOwner.enterCode(enteredCode) { result in
                                    isSubmittingCode = false
                                    switch result {
                                    case .success:
                                        enteredCode = ""
                                        loadDatabases()
                                    case .failure(let err):
                                        codeError = err.localizedDescription
                                    }
                                }
                            } label: {
                                HStack {
                                    Text("Add access")
                                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                                    if isSubmittingCode {
                                        Spacer()
                                        ProgressView()
                                            .scaleEffect(0.9)
                                            .tint(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Capsule().fill(Color(red: 1, green: 0.45, blue: 0.3)))
                                .foregroundStyle(.black)
                            }
                            .buttonStyle(.plain)
                            .disabled(enteredCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmittingCode)
                        } header: {
                            Text("Get edit access to another database")
                                .foregroundStyle(.white.opacity(0.7))
                        } footer: {
                            Text("Enter a code from someone to add or edit their database. You can then tap it in the list below.")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                        .listRowSeparatorTint(.white.opacity(0.15))

                        if auth.isSignedIn, dbOwner.myDbId != nil {
                            Section {
                                Button {
                                    import2026Error = nil
                                    showImport2026Confirm = true
                                } label: {
                                    HStack {
                                        Label("Import 2026 doubles from stats.db", systemImage: "square.and.arrow.down")
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                        if isImporting2026 {
                                            Spacer()
                                            Text(import2026Progress)
                                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                                .foregroundStyle(.white.opacity(0.7))
                                            ProgressView()
                                                .scaleEffect(0.9)
                                                .tint(Color(red: 1, green: 0.45, blue: 0.3))
                                        }
                                    }
                                }
                                .disabled(isImporting2026)
                                if let err = import2026Error {
                                    Text(err)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                                }
                            } header: {
                                Text("Import data")
                                    .foregroundStyle(.white.opacity(0.7))
                            } footer: {
                                Text("Imports all 2026 doubles games from a bundled stats.db into your database. Add stats.db to the Xcode project.")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                            .listRowSeparatorTint(.white.opacity(0.15))
                        }

                        Section {
                            if auth.isSignedIn {
                                HStack {
                                    Label(auth.userEmail ?? "Signed in", systemImage: "person.crop.circle.fill")
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.9))
                                    Spacer()
                                    Button("Sign out") {
                                        auth.signOut()
                                        dbOwner.refreshAdminStatus()
                                    }
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                }
                            } else {
                                Button {
                                    signInError = nil
                                    isSigningIn = true
                                    auth.signInWithGoogle { result in
                                        isSigningIn = false
                                        switch result {
                                        case .success:
                                            dbOwner.refreshAdminStatus()
                                        case .failure(let err):
                                            signInError = err.localizedDescription
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Label("Sign in with Google", systemImage: "person.crop.circle.badge.plus")
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                        if isSigningIn {
                                            Spacer()
                                            ProgressView()
                                                .scaleEffect(0.9)
                                                .tint(Color(red: 1, green: 0.45, blue: 0.3))
                                        }
                                    }
                                }
                                .disabled(isSigningIn)
                                if let err = signInError {
                                    Text(err)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                                }
                            }
                        } header: {
                            Text("Account")
                                .foregroundStyle(.white.opacity(0.7))
                        } footer: {
                            if !auth.isSignedIn {
                                Text("Sign in to use admin on any device. Add your Supabase user ID to config admin_uids in Supabase to get admin.")
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                        .listRowSeparatorTint(.white.opacity(0.15))
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Databases")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.06, green: 0.1, blue: 0.16), for: .navigationBar)
            .task {
                loadDatabases()
            }
            .refreshable {
                loadDatabases()
            }
            .navigationDestination(for: DatabaseListItem.self) { db in
                DatabaseView(dbId: db.id, displayName: db.displayName)
            }
            .sheet(isPresented: $showDatabaseNameSheet) {
                databaseNameSheet
            }
            .sheet(isPresented: $showRenameSheet) {
                renameDatabaseSheet
            }
            .sheet(isPresented: $showAdminActivity) {
                AdminActivityView()
            }
            .sheet(isPresented: $showAdminPlayers) {
                AdminPlayersView()
            }
            .alert("Delete database?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { showDeleteConfirm = false }
                Button("Delete", role: .destructive) {
                    performDelete()
                }
            } message: {
                Text("Delete \"\(databaseToDelete?.displayName ?? dbOwner.myDatabaseDisplayName)\"? All games will be removed. This cannot be undone.")
            }
            .alert("Share code", isPresented: Binding(get: { createdCode != nil }, set: { if !$0 { createdCode = nil } })) {
                Button("Copy") {
                    if let code = createdCode { UIPasteboard.general.string = code }
                    createdCode = nil
                }
                Button("OK", role: .cancel) { createdCode = nil }
            } message: {
                if let code = createdCode {
                    Text("Share this code with others; anyone who enters it can add or edit games in your database.\n\n\(code)")
                }
            }
            .alert("Recalculate stats", isPresented: $showRecalcStatsConfirm) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Stats have been recalculated from all games. Open the Stats tab to see them.")
            }
            .alert("Import 2026 doubles?", isPresented: $showImport2026Confirm) {
                Button("Cancel", role: .cancel) { showImport2026Confirm = false }
                Button("Import") {
                    showImport2026Confirm = false
                    startImport2026IntoMyDatabase()
                }
            } message: {
                Text("This will add all 2026 doubles games from stats.db (or doubles_games.json) into your database. Existing games are not removed.")
            }
            .task {
                dbOwner.refreshAdminStatus()
            }
        }
    }

    private var databaseNameSheet: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.12, blue: 0.18).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    Text("Name your database")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    TextField("e.g. Weekend Games", text: $databaseNameInput)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                    Text("This name is saved in the cloud and shown to everyone when they browse databases. It must be unique.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    if let err = uploadError {
                        Text(err)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("New database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.12, blue: 0.18), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showDatabaseNameSheet = false
                        databaseNameInput = ""
                        uploadError = nil
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        uploadError = nil
                        isUploading = true
                        dbOwner.uploadLocalToMyDatabase(displayName: databaseNameInput) { result in
                            isUploading = false
                            switch result {
                            case .success:
                                showDatabaseNameSheet = false
                                databaseNameInput = ""
                                loadDatabases()
                            case .failure(let err):
                                uploadError = err.localizedDescription
                            }
                        }
                    }
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    .disabled(databaseNameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUploading)
                }
            }
        }
    }

    private var renameDatabaseSheet: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.12, blue: 0.18).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    Text("Rename your database")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    TextField("Database name", text: $renameInput)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                    Text("This name must be unique. Others will see it when browsing.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    if let err = renameError {
                        Text(err)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Rename database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.12, blue: 0.18), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRenameSheet = false
                        renameInput = ""
                        renameError = nil
                        databaseToRename = nil
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        renameError = nil
                        isRenaming = true
                        let name = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if databaseToRename?.id == dbOwner.myDbId {
                            dbOwner.renameMyDatabase(newDisplayName: name) { result in
                                isRenaming = false
                                switch result {
                                case .success:
                                    showRenameSheet = false
                                    renameInput = ""
                                    databaseToRename = nil
                                    loadDatabases()
                                case .failure(let err):
                                    renameError = err.localizedDescription
                                }
                            }
                        } else if let db = databaseToRename {
                            cloud.renameDatabase(dbId: db.id, currentDisplayName: db.displayName, newDisplayName: name) { result in
                                isRenaming = false
                                switch result {
                                case .success:
                                    showRenameSheet = false
                                    renameInput = ""
                                    databaseToRename = nil
                                    loadDatabases()
                                case .failure(let err):
                                    renameError = err.localizedDescription
                                }
                            }
                        } else {
                            isRenaming = false
                        }
                    }
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    .disabled(renameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRenaming)
                }
            }
        }
    }

    private func startImport2026IntoMyDatabase() {
        guard let dbId = dbOwner.myDbId else { return }
        isImporting2026 = true
        import2026Error = nil
        import2026Progress = "Loading…"
        StatsDB2026Importer.load2026DoublesGames { [self] result in
            switch result {
            case .failure(let err):
                DispatchQueue.main.async {
                    import2026Error = err.localizedDescription
                    isImporting2026 = false
                    import2026Progress = ""
                }
                return
            case .success(let games):
                let total = games.count
                if total == 0 {
                    DispatchQueue.main.async {
                        import2026Progress = ""
                        import2026Error = "No 2026 doubles games found."
                        isImporting2026 = false
                    }
                    return
                }
                insertNext2026Game(dbId: dbId, games: games, index: 0, total: total)
            }
        }
    }

    private func insertNext2026Game(dbId: String, games: [StatsDB2026Importer.GameRow], index: Int, total: Int) {
        guard index < games.count else {
            cloud.setStatsRecomputeRequired(dbId: dbId) {
                DispatchQueue.main.async { [self] in
                    isImporting2026 = false
                    import2026Progress = "Done. \(total) games imported."
                    import2026Error = nil
                }
            }
            return
        }
        let row = games[index]
        cloud.insertGame(dbId: dbId, date: row.date, winner1: row.winner1, winner2: row.winner2, winnerScore: row.winnerScore, loser1: row.loser1, loser2: row.loser2, loserScore: row.loserScore, comment: row.comment, editorDbId: nil) { [self] result in
            DispatchQueue.main.async {
                import2026Progress = "\(index + 1)/\(total)"
            }
            switch result {
            case .success:
                insertNext2026Game(dbId: dbId, games: games, index: index + 1, total: total)
            case .failure(let err):
                DispatchQueue.main.async {
                    import2026Error = "Game \(index + 1) failed: \(err.localizedDescription)"
                    isImporting2026 = false
                    import2026Progress = ""
                }
            }
        }
    }

    private func performDelete() {
        isDeleting = true
        if let db = databaseToDelete {
            cloud.deleteDatabase(dbId: db.id, displayName: db.displayName) { [self] result in
                isDeleting = false
                showDeleteConfirm = false
                databaseToDelete = nil
                switch result {
                case .success:
                    loadDatabases()
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        } else {
            dbOwner.deleteMyDatabase { [self] result in
                isDeleting = false
                showDeleteConfirm = false
                switch result {
                case .success:
                    loadDatabases()
                case .failure(let err):
                    errorMessage = err.localizedDescription
                }
            }
        }
    }

    @ViewBuilder
    private func databaseRow(db: DatabaseListItem, isMyDatabase: Bool) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "chart.bar.doc.plain")
                .font(.title2)
                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
            if isMyDatabase {
                VStack(alignment: .leading, spacing: 2) {
                    Text("My database")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text(db.displayName)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                Text(db.displayName)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
    }

    private func loadDatabases() {
        isLoading = true
        errorMessage = nil
        cloud.listDatabases { [self] result in
            isLoading = false
            switch result {
            case .success(let list):
                databases = list.map { DatabaseListItem(id: $0.id, displayName: $0.displayName) }
                // If our database appears as "Unnamed" in the cloud, push our local name so other devices see it (unless it's still default).
                if let myId = dbOwner.myDbId,
                   let myDb = list.first(where: { $0.id == myId }),
                   myDb.displayName == "Unnamed" || myDb.displayName.lowercased() == "unnamed" {
                    myDatabaseIsUnnamedInCloud = true
                    let localName = dbOwner.myDatabaseDisplayName
                    if !localName.isEmpty && localName != "My database" {
                        cloud.renameDatabase(dbId: myId, currentDisplayName: myDb.displayName, newDisplayName: localName) { _ in
                            myDatabaseIsUnnamedInCloud = false
                            loadDatabases()
                        }
                    }
                } else {
                    myDatabaseIsUnnamedInCloud = false
                }
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }
}

// MARK: - Full database view (Stats + Games tabs, same as main app)

struct DatabaseView: View {
    let dbId: String
    let displayName: String
    @Environment(\.dismiss) private var dismiss
    @State private var games: [LegacyGame] = []
    @State private var isLoading = false
    @State private var selectedYear: String = String(Calendar.current.component(.year, from: Date()))
    @State private var showingAddGame = false
    @State private var gameToEdit: LegacyGame?
    @State private var showRenameSheet = false
    @State private var renameInput = ""
    @State private var renameError: String?
    @State private var isRenaming = false
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    /// After admin renames another user's database, we show the new name in the nav title.
    @State private var renamedDisplayName: String?
    @ObservedObject private var dbOwner = DatabaseOwnerManager.shared

    private var isOwner: Bool { dbId == dbOwner.myDbId }
    private var effectiveDisplayName: String { isOwner ? dbOwner.myDatabaseDisplayName : (renamedDisplayName ?? displayName) }

    private var yearsWithGames: [String] {
        let calendar = Calendar.current
        let currentYear = calendar.component(.year, from: Date())
        var uniqueYears = games.isEmpty ? Set<Int>() : Set(games.map { calendar.component(.year, from: $0.date) })
        uniqueYears.insert(currentYear)
        return ["All"] + uniqueYears.sorted(by: >).map { String($0) }
    }

    private var filteredGames: [LegacyGame] {
        if selectedYear == "All" { return games }
        let calendar = Calendar.current
        return games.filter { String(calendar.component(.year, from: $0.date)) == selectedYear }
    }

    private var canEdit: Bool { dbOwner.canEdit(dbId: dbId) }

    var body: some View {
        TabView {
            StatsPageView(
                games: filteredGames,
                isLoading: isLoading,
                selectedYear: $selectedYear,
                yearsWithGames: yearsWithGames,
                statsSource: .constant(.other(dbId: dbId, displayName: effectiveDisplayName)),
                sourceDisplayName: effectiveDisplayName,
                canShowMyDatabase: false,
                canEdit: canEdit,
                onRefresh: loadGames,
                onAdd: { gameToEdit = nil; showingAddGame = true },
                onOpenDatabases: {}
            )
            .tabItem {
                Label("Stats", systemImage: "chart.bar.fill")
            }

            GamesPageView(
                games: $games,
                filteredGames: filteredGames,
                isLoading: isLoading,
                selectedYear: $selectedYear,
                yearsWithGames: yearsWithGames,
                statsSource: .constant(.other(dbId: dbId, displayName: effectiveDisplayName)),
                sourceDisplayName: effectiveDisplayName,
                canShowMyDatabase: false,
                canEdit: canEdit,
                onAdd: { gameToEdit = nil; showingAddGame = true },
                onEdit: { gameToEdit = $0; showingAddGame = true },
                onDelete: deleteGame,
                onGamesChanged: loadGames,
                onOpenDatabases: {}
            )
            .tabItem {
                Label("Games", systemImage: "list.bullet")
            }
        }
        .tint(Color(red: 1, green: 0.45, blue: 0.3))
        .navigationTitle(isOwner ? dbOwner.myDatabaseDisplayName : displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color(red: 0.06, green: 0.1, blue: 0.16), for: .navigationBar)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            renameInput = dbOwner.myDatabaseDisplayName
                            renameError = nil
                            showRenameSheet = true
                        } label: { Label("Rename", systemImage: "pencil") }
                        Button(role: .destructive) {
                            showDeleteConfirm = true
                        } label: { Label("Delete database", systemImage: "trash") }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .task {
            loadGames()
        }
        .onChange(of: yearsWithGames) { _, newYears in
            if !newYears.contains(selectedYear) { selectedYear = newYears.first { $0 != "All" } ?? "All" }
        }
        .sheet(isPresented: $showingAddGame, onDismiss: { gameToEdit = nil }) {
            AddGameView(gameToEdit: gameToEdit, statsSource: .other(dbId: dbId, displayName: effectiveDisplayName), cloudDbId: dbId, editorDbId: dbOwner.myDbId, onSave: {
                loadGames()
            })
        }
        .sheet(isPresented: $showRenameSheet) {
            databaseViewRenameSheet
        }
        .alert("Delete database?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) { showDeleteConfirm = false }
            Button("Delete", role: .destructive) {
                performDeleteFromDatabaseView()
            }
        } message: {
            Text("Delete \"\(effectiveDisplayName)\"? All games will be removed. This cannot be undone.")
        }
    }

    private var databaseViewRenameSheet: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.12, blue: 0.18).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 20) {
                    Text("Rename your database")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                    TextField("Database name", text: $renameInput)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                    Text("This name must be unique. Others will see it when browsing.")
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                    if let err = renameError {
                        Text(err)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Rename database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.12, blue: 0.18), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showRenameSheet = false
                        renameInput = ""
                        renameError = nil
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        renameError = nil
                        isRenaming = true
                        let name = renameInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        if isOwner {
                            dbOwner.renameMyDatabase(newDisplayName: name) { result in
                                isRenaming = false
                                switch result {
                                case .success:
                                    showRenameSheet = false
                                    renameInput = ""
                                case .failure(let err):
                                    renameError = err.localizedDescription
                                }
                            }
                        } else {
                            cloud.renameDatabase(dbId: dbId, currentDisplayName: effectiveDisplayName, newDisplayName: name) { result in
                                isRenaming = false
                                switch result {
                                case .success:
                                    renamedDisplayName = name
                                    showRenameSheet = false
                                    renameInput = ""
                                case .failure(let err):
                                    renameError = err.localizedDescription
                                }
                            }
                        }
                    }
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    .disabled(renameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRenaming)
                }
            }
        }
    }

    private func performDeleteFromDatabaseView() {
        isDeleting = true
        if isOwner {
            dbOwner.deleteMyDatabase { result in
                isDeleting = false
                showDeleteConfirm = false
                switch result {
                case .success:
                    dismiss()
                case .failure:
                    break
                }
            }
        } else {
            cloud.deleteDatabase(dbId: dbId, displayName: effectiveDisplayName) { result in
                isDeleting = false
                showDeleteConfirm = false
                switch result {
                case .success:
                    dismiss()
                case .failure:
                    break
                }
            }
        }
    }

    private func loadGames() {
        isLoading = true
        cloud.fetchGames(dbId: dbId, limit: 25) { [self] result in
            isLoading = false
            if case .success(let loaded) = result {
                games = loaded
            }
        }
    }

    private func deleteGame(_ game: LegacyGame) {
        guard let recordName = game.recordName else { return }
        cloud.deleteGame(dbId: dbId, documentId: recordName, editorDbId: dbOwner.myDbId) { [self] result in
            if case .success = result {
                games.removeAll { $0.recordName == recordName }
            }
        }
    }

}

// MARK: - Admin: manage all databases (admin only)

struct AdminAllDatabasesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var databases: [(id: String, displayName: String)] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var renamingDbId: String?
    @State private var renameInput = ""
    @State private var renameError: String?
    @State private var deletingDbId: String?
    @State private var dbToDelete: (id: String, displayName: String)?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.12, blue: 0.18).ignoresSafeArea()
                if isLoading {
                    ProgressView().scaleEffect(1.5).tint(Color(red: 1, green: 0.45, blue: 0.3))
                } else if let err = errorMessage {
                    Text(err).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding()
                } else {
                    List {
                        ForEach(databases, id: \.id) { db in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(db.displayName)
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white)
                                    Text(db.id)
                                        .font(.system(size: 12, weight: .regular))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                Spacer()
                                Menu {
                                    Button {
                                        renamingDbId = db.id
                                        renameInput = db.displayName
                                        renameError = nil
                                    } label: { Label("Rename", systemImage: "pencil") }
                                    Button(role: .destructive) {
                                        dbToDelete = (db.id, db.displayName)
                                    } label: { Label("Delete", systemImage: "trash") }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.title3)
                                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                }
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("All databases")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.12, blue: 0.18), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                }
            }
            .task { load() }
            .sheet(isPresented: Binding(get: { renamingDbId != nil }, set: { if !$0 { renamingDbId = nil } })) {
                if let dbId = renamingDbId, let db = databases.first(where: { $0.id == dbId }) {
                    AdminRenameSheet(dbId: dbId, currentName: db.displayName, renameInput: $renameInput, error: $renameError) {
                        renamingDbId = nil
                        load()
                    }
                }
            }
            .alert("Delete database?", isPresented: Binding(get: { dbToDelete != nil }, set: { if !$0 { dbToDelete = nil } })) {
                Button("Cancel", role: .cancel) { dbToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let d = dbToDelete {
                        cloud.deleteDatabase(dbId: d.id, displayName: d.displayName) { _ in
                            dbToDelete = nil
                            load()
                        }
                    }
                }
            } message: {
                if let d = dbToDelete {
                    Text("Delete \"\(d.displayName)\"? All games will be removed. This cannot be undone.")
                }
            }
        }
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        cloud.listDatabases { result in
            isLoading = false
            switch result {
            case .success(let list): databases = list
            case .failure(let err): errorMessage = err.localizedDescription
            }
        }
    }
}

private struct AdminRenameSheet: View {
    @Environment(\.dismiss) private var dismiss
    let dbId: String
    let currentName: String
    @Binding var renameInput: String
    @Binding var error: String?
    let onSuccess: () -> Void

    @State private var isRenaming = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.12, blue: 0.18).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 16) {
                    TextField("Display name", text: $renameInput)
                        .textInputAutocapitalization(.words)
                        .padding(12)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.white)
                    if let err = error {
                        Text(err).font(.system(size: 13)).foregroundStyle(Color(red: 1, green: 0.4, blue: 0.35))
                    }
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Rename database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Rename") {
                        error = nil
                        isRenaming = true
                        cloud.renameDatabase(dbId: dbId, currentDisplayName: currentName, newDisplayName: renameInput) { result in
                            isRenaming = false
                            switch result {
                            case .success:
                                onSuccess()
                                dismiss()
                            case .failure(let err): error = err.localizedDescription
                            }
                        }
                    }
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    .disabled(renameInput.trimmingCharacters(in: .whitespaces).isEmpty || isRenaming)
                }
            }
        }
    }
}

// MARK: - Admin: activity log (admin only)

private struct ActivityItemWithDb: Identifiable {
    let id: String
    let dbDisplayName: String
    let entry: ActivityEntry
}

struct AdminActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var databases: [(id: String, displayName: String)] = []
    @State private var activityByDb: [String: [ActivityEntry]] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var allChangesChronological: [ActivityItemWithDb] {
        var items: [ActivityItemWithDb] = []
        for db in databases {
            let entries = activityByDb[db.id] ?? []
            for entry in entries {
                items.append(ActivityItemWithDb(id: "\(db.id)-\(entry.id)", dbDisplayName: db.displayName, entry: entry))
            }
        }
        return items.sorted { $0.entry.at > $1.entry.at }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.12, blue: 0.18).ignoresSafeArea()
                if isLoading {
                    ProgressView().scaleEffect(1.5).tint(Color(red: 1, green: 0.45, blue: 0.3))
                } else if let err = errorMessage {
                    Text(err).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding()
                } else {
                    List {
                        Section {
                            let all = allChangesChronological
                            if all.isEmpty {
                                Text("No changes yet")
                                    .font(.system(size: 14))
                                    .foregroundStyle(.white.opacity(0.6))
                            } else {
                                ForEach(all.prefix(100)) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(item.entry.action == "add_game" ? "Added game" : item.entry.action == "update_game" ? "Updated game" : "Deleted game")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(.white)
                                            Text("·")
                                                .foregroundStyle(.white.opacity(0.5))
                                            Text(item.dbDisplayName)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                                        }
                                        if let s = item.entry.summary {
                                            Text(s).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                                        }
                                        Text(item.entry.at, style: .relative)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                    .listRowBackground(Color.white.opacity(0.06))
                                }
                            }
                        } header: {
                            Text("All changes")
                                .foregroundStyle(.white.opacity(0.8))
                        } footer: {
                            Text("All add, update, and delete activity across every database. Sorted by most recent.")
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        .listRowBackground(Color.white.opacity(0.06))

                        ForEach(databases, id: \.id) { db in
                            let entries = activityByDb[db.id] ?? []
                            Section {
                                if entries.isEmpty {
                                    Text("No recent activity")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.white.opacity(0.6))
                                } else {
                                    ForEach(entries.prefix(50)) { entry in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.action == "add_game" ? "Added game" : entry.action == "update_game" ? "Updated game" : "Deleted game")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundStyle(.white)
                                            if let s = entry.summary {
                                                Text(s).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                                            }
                                            Text(entry.at, style: .relative)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.white.opacity(0.5))
                                        }
                                        .listRowBackground(Color.white.opacity(0.06))
                                    }
                                }
                            } header: {
                                Text(db.displayName)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            .listRowBackground(Color.white.opacity(0.06))
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Activity log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.12, blue: 0.18), for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                }
            }
            .task { load() }
        }
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        cloud.listDatabases { result in
            switch result {
            case .success(let list):
                databases = list
                if list.isEmpty {
                    activityByDb = [:]
                    isLoading = false
                    return
                }
                var merged: [String: [ActivityEntry]] = [:]
                let group = DispatchGroup()
                for db in list {
                    group.enter()
                    cloud.fetchActivity(dbId: db.id, limit: 100) { res in
                        if case .success(let entries) = res {
                            merged[db.id] = entries
                        }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    activityByDb = merged
                    isLoading = false
                }
            case .failure(let err):
                errorMessage = err.localizedDescription
                isLoading = false
            }
        }
    }
}

// MARK: - Admin: manage players (admin only)

struct AdminPlayersView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var databases: [(id: String, displayName: String)] = []
    @State private var selectedDbId: String?
    @State private var selectedDbName: String = ""
    @State private var players: [AdminPlayerRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var playerToEdit: AdminPlayerRow?
    @State private var showAddPlayer = false
    @State private var playerToDelete: AdminPlayerRow?
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.08, green: 0.12, blue: 0.18).ignoresSafeArea()
                if isLoading {
                    ProgressView().scaleEffect(1.5).tint(Color(red: 1, green: 0.45, blue: 0.3))
                } else if let err = errorMessage {
                    Text(err).foregroundStyle(.white.opacity(0.8)).multilineTextAlignment(.center).padding()
                } else if let dbId = selectedDbId {
                    playersListView(dbId: dbId)
                } else {
                    databaseListView
                }
            }
            .navigationTitle(selectedDbId != nil ? "Players · \(selectedDbName)" : "Manage players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.12, blue: 0.18), for: .navigationBar)
            .toolbar {
                if selectedDbId != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") {
                            selectedDbId = nil
                            selectedDbName = ""
                        }
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add player") {
                            showAddPlayer = true
                        }
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                }
            }
            .task { if selectedDbId == nil { loadDatabases() } }
            .onChange(of: selectedDbId) { _, new in
                if let id = new { loadPlayers(dbId: id) }
            }
            .sheet(item: $playerToEdit) { p in
                EditPlayerSheet(
                    player: p,
                    onSave: { displayName, firstName, lastName in
                        guard let dbId = selectedDbId else { return }
                        cloud.updatePlayer(dbId: dbId, docId: p.docId, displayName: displayName, firstName: firstName, lastName: lastName) { result in
                            switch result {
                            case .success:
                                playerToEdit = nil
                                loadPlayers(dbId: dbId)
                            case .failure(let err):
                                saveError = err.localizedDescription
                            }
                        }
                    },
                    onDismiss: { playerToEdit = nil }
                )
            }
            .sheet(isPresented: $showAddPlayer) {
                AddPlayerSheet(
                    onSave: { displayName, firstName, lastName in
                        guard let dbId = selectedDbId else { return }
                        cloud.insertPlayer(dbId: dbId, displayName: displayName, firstName: firstName, lastName: lastName) { result in
                            switch result {
                            case .success:
                                showAddPlayer = false
                                loadPlayers(dbId: dbId)
                            case .failure(let err):
                                saveError = err.localizedDescription
                            }
                        }
                    },
                    onDismiss: { showAddPlayer = false }
                )
            }
            .alert("Error", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: {
                if let err = saveError { Text(err) }
            }
            .alert("Delete player?", isPresented: Binding(get: { playerToDelete != nil }, set: { if !$0 { playerToDelete = nil } })) {
                Button("Cancel", role: .cancel) { playerToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let p = playerToDelete, let dbId = selectedDbId {
                        cloud.deletePlayer(dbId: dbId, docId: p.docId) { _ in
                            loadPlayers(dbId: dbId)
                        }
                        playerToDelete = nil
                    }
                }
            } message: {
                if let p = playerToDelete {
                    Text("Remove \"\(p.displayName)\" from the players list? Games that reference this name are not changed.")
                }
            }
        }
    }

    private var databaseListView: some View {
        List {
            ForEach(databases, id: \.id) { db in
                Button {
                    selectedDbId = db.id
                    selectedDbName = db.displayName
                } label: {
                    HStack {
                        Text(db.displayName)
                            .foregroundStyle(.white)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .listRowBackground(Color.white.opacity(0.06))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func playersListView(dbId: String) -> some View {
        List {
            if players.isEmpty {
                Text("No players in this database yet. Add players or add games to create them.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .listRowBackground(Color.white.opacity(0.06))
            } else {
                ForEach(players) { p in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.displayName)
                                .font(.system(size: 16, weight: .medium))
                                .foregroundStyle(.white)
                            if let f = p.firstName, let l = p.lastName, !f.isEmpty || !l.isEmpty {
                                Text([f, l].filter { !$0.isEmpty }.joined(separator: " "))
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        Spacer()
                        Button {
                            playerToEdit = p
                        } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 14))
                                .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                        }
                    }
                    .listRowBackground(Color.white.opacity(0.06))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playerToEdit = p
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            playerToDelete = p
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func loadDatabases() {
        isLoading = true
        errorMessage = nil
        cloud.listDatabases { result in
            switch result {
            case .success(let list):
                databases = list
                isLoading = false
            case .failure(let err):
                errorMessage = err.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadPlayers(dbId: String) {
        isLoading = true
        cloud.fetchPlayerRows(dbId: dbId) { result in
            isLoading = false
            switch result {
            case .success(let list):
                players = list
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
        }
    }
}

private struct EditPlayerSheet: View {
    let player: AdminPlayerRow
    let onSave: (String, String?, String?) -> Void
    let onDismiss: () -> Void
    @State private var displayName: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Display name", text: $displayName)
                TextField("First name (optional)", text: $firstName)
                TextField("Last name (optional)", text: $lastName)
            }
            .navigationTitle("Edit player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = displayName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        onSave(name, firstName.isEmpty ? nil : firstName, lastName.isEmpty ? nil : lastName)
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                displayName = player.displayName
                firstName = player.firstName ?? ""
                lastName = player.lastName ?? ""
            }
        }
    }
}

private struct AddPlayerSheet: View {
    let onSave: (String, String?, String?) -> Void
    let onDismiss: () -> Void
    @State private var displayName: String = ""
    @State private var firstName: String = ""
    @State private var lastName: String = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Display name", text: $displayName)
                TextField("First name (optional)", text: $firstName)
                TextField("Last name (optional)", text: $lastName)
            }
            .navigationTitle("Add player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onDismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = displayName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        onSave(name, firstName.isEmpty ? nil : firstName, lastName.isEmpty ? nil : lastName)
                    }
                    .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
