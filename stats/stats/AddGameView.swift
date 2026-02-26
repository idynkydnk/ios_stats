import SwiftUI

struct AddGameView: View {
    @Environment(\.dismiss) private var dismiss
    
    var gameToEdit: LegacyGame? = nil
    var onSave: (() -> Void)?
    
    // Players
    @State private var winner1: String
    @State private var winner2: String
    @State private var loser1: String
    @State private var loser2: String
    
    // Scores
    @State private var winnerScore: Int
    @State private var loserScore: Int
    
    // Autocomplete
    @State private var allPlayers: [PlayerInfo] = []
    @State private var recentPlayers: [PlayerInfo] = []
    @State private var activeStep: AddGameStep?
    @State private var showPlayerOverlay = false
    @FocusState private var focusedField: PlayerField?
    
    // Common scores from the database
    private let commonWinnerScores = [21, 22, 23, 24, 25, 15]
    private let commonLoserScores = [19, 18, 17, 16, 15, 14, 13, 12, 11, 10, 9, 0]
    
    init(gameToEdit: LegacyGame? = nil, onSave: (() -> Void)? = nil) {
        self.gameToEdit = gameToEdit
        self.onSave = onSave
        if let g = gameToEdit {
            _winner1 = State(initialValue: g.winner1)
            _winner2 = State(initialValue: g.winner2)
            _loser1 = State(initialValue: g.loser1)
            _loser2 = State(initialValue: g.loser2)
            _winnerScore = State(initialValue: g.winnerScore)
            _loserScore = State(initialValue: g.loserScore)
        } else {
            _winner1 = State(initialValue: "")
            _winner2 = State(initialValue: "")
            _loser1 = State(initialValue: "")
            _loser2 = State(initialValue: "")
            _winnerScore = State(initialValue: 21)
            _loserScore = State(initialValue: 19)
        }
    }
    
    enum PlayerField: Hashable {
        case winner1, winner2, loser1, loser2
    }
    
    enum AddGameStep: Hashable {
        case winner1, winner2, loser1, loser2, winnerScore, loserScore
    }
    
    private func nextStep(after step: AddGameStep) -> AddGameStep? {
        switch step {
        case .winner1: return .winner2
        case .winner2: return .loser1
        case .loser1: return .loser2
        case .loser2: return .winnerScore
        case .winnerScore: return .loserScore
        case .loserScore: return nil
        }
    }
    
    private var isValid: Bool {
        !winner1.trimmingCharacters(in: .whitespaces).isEmpty &&
        !winner2.trimmingCharacters(in: .whitespaces).isEmpty &&
        !loser1.trimmingCharacters(in: .whitespaces).isEmpty &&
        !loser2.trimmingCharacters(in: .whitespaces).isEmpty &&
        winnerScore > loserScore
    }
    
    private func searchPlayers(_ searchText: String) -> [PlayerInfo] {
        if searchText.isEmpty { return recentPlayers }
        let lowercased = searchText.lowercased()
        return allPlayers.filter { $0.name.lowercased().contains(lowercased) }
            .prefix(12)
            .map { $0 }
    }
    
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
                
                ScrollView {
                    VStack(spacing: 20) {
                        teamSection(
                            title: "WINNERS",
                            color: Color(red: 0.3, green: 0.85, blue: 0.6),
                            player1: $winner1,
                            player2: $winner2,
                            player1Field: .winner1,
                            player2Field: .winner2,
                            score: $winnerScore,
                            commonScores: commonWinnerScores,
                            focusedField: $focusedField
                        )
                        
                        teamSection(
                            title: "LOSERS",
                            color: Color(red: 1, green: 0.4, blue: 0.35),
                            player1: $loser1,
                            player2: $loser2,
                            player1Field: .loser1,
                            player2Field: .loser2,
                            score: $loserScore,
                            commonScores: commonLoserScores,
                            focusedField: $focusedField
                        )
                        
                        Button {
                            saveGame()
                        } label: {
                            Text(gameToEdit == nil ? "Save Game" : "Update Game")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    RoundedRectangle(cornerRadius: 14)
                                        .fill(isValid ? Color(red: 1, green: 0.45, blue: 0.3) : Color.gray.opacity(0.4))
                                )
                        }
                        .disabled(!isValid)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 16)
                }
                
                // Full-screen player picker (covers most of screen)
                if let step = activeStep, step.isPlayerStep, showPlayerOverlay {
                    fullScreenPlayerOverlay(step: step)
                }
                
                // Full-screen score picker
                if activeStep == .winnerScore {
                    fullScreenScoreOverlay(
                        title: "Winner score",
                        scores: commonWinnerScores,
                        color: Color(red: 0.3, green: 0.85, blue: 0.6)
                    ) { score in
                        winnerScore = score
                        activeStep = .loserScore
                    }
                }
                if activeStep == .loserScore {
                    fullScreenScoreOverlay(
                        title: "Loser score",
                        scores: commonLoserScores,
                        color: Color(red: 1, green: 0.4, blue: 0.35)
                    ) { score in
                        loserScore = score
                        activeStep = nil
                    }
                }
            }
            .navigationTitle(gameToEdit == nil ? "Add Game" : "Edit Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                }
            }
            .onAppear {
                loadPlayers()
                if gameToEdit == nil {
                    Task {
                        try? await Task.sleep(nanoseconds: 350_000_000)
                        await MainActor.run {
                            activeStep = .winner1
                            focusedField = .winner1
                            showPlayerOverlay = true
                        }
                    }
                }
            }
        }
    }
    
    private func fullScreenPlayerOverlay(step: AddGameStep) -> some View {
        let suggestions = stepSuggestions(for: step)
        return
            VStack(spacing: 0) {
                // Header with "Type name" to switch to keyboard
                HStack {
                    Text(step.placeholderTitle)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                    Button {
                        showPlayerOverlay = false
                        focusedField = step.playerField
                    } label: {
                        Label("Type name", systemImage: "keyboard")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    }
                    Button {
                        showPlayerOverlay = false
                        activeStep = nil
                        focusedField = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color(red: 0.08, green: 0.12, blue: 0.18))
                
                Divider().background(Color.white.opacity(0.2))
                
                // Scrollable grid of players
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(suggestions.prefix(20)) { player in
                            Button {
                                selectPlayer(player.name, from: step)
                            } label: {
                                HStack {
                                    Text(player.name)
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(player.gameCount)")
                                        .font(.system(size: 12, weight: .regular, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .foregroundStyle(.white)
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .frame(maxHeight: .infinity)
            }
            .background(Color(red: 0.06, green: 0.1, blue: 0.16))
            .transition(.opacity)
    }
    
    private func stepSuggestions(for step: AddGameStep) -> [PlayerInfo] {
        switch step {
        case .winner1: return searchPlayers(winner1)
        case .winner2: return searchPlayers(winner2)
        case .loser1: return searchPlayers(loser1)
        case .loser2: return searchPlayers(loser2)
        case .winnerScore, .loserScore: return []
        }
    }
    
    private func fullScreenScoreOverlay(
        title: String,
        scores: [Int],
        color: Color,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    activeStep = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(color.opacity(0.3))
            
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(scores, id: \.self) { score in
                        Button {
                            onSelect(score)
                        } label: {
                            Text("\(score)")
                                .font(.system(size: 24, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(color.opacity(0.4))
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .frame(maxHeight: .infinity)
        }
        .background(Color(red: 0.06, green: 0.1, blue: 0.16))
    }
    
    @ViewBuilder
    private func teamSection(
        title: String,
        color: Color,
        player1: Binding<String>,
        player2: Binding<String>,
        player1Field: PlayerField,
        player2Field: PlayerField,
        score: Binding<Int>,
        commonScores: [Int],
        focusedField: FocusState<PlayerField?>.Binding
    ) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(color)
            
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    playerField(text: player1, field: player1Field, focusedField: focusedField)
                    playerField(text: player2, field: player2Field, focusedField: focusedField)
                }
                
                let selectedPlayers = [winner1, winner2, loser1, loser2]
                let availablePlayers = recentPlayers.filter { !selectedPlayers.contains($0.name) }.prefix(6)
                if !availablePlayers.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(availablePlayers), id: \.name) { player in
                                Button {
                                    assignPlayer(player.name, to: player1Field, or: player2Field, player1: player1, player2: player2)
                                } label: {
                                    Text(player.name.components(separatedBy: " ").first ?? player.name)
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(color.opacity(0.3))
                                        .foregroundStyle(.white)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
                
                // Score: tappable like players
                HStack(spacing: 12) {
                    Text("Score:")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(commonScores, id: \.self) { s in
                                Button {
                                    score.wrappedValue = s
                                } label: {
                                    Text("\(s)")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(score.wrappedValue == s ? .black : .white)
                                        .frame(minWidth: 44)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(score.wrappedValue == s ? color : color.opacity(0.4))
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .background(Color.white.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 16)
    }
    
    @ViewBuilder
    private func playerField(
        text: Binding<String>,
        field: PlayerField,
        focusedField: FocusState<PlayerField?>.Binding
    ) -> some View {
        let placeholder = field == .winner1 || field == .winner2 ? "Player" : "Player"
        HStack(spacing: 6) {
            TextField(placeholder, text: text)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.words)
                .focused(focusedField, equals: field)
                .onChange(of: text.wrappedValue) { _, _ in
                    if activeStep == nil || activeStep?.playerField == field {
                        activeStep = field.toStep
                    }
                }
                .onTapGesture {
                    activeStep = field.toStep
                    showPlayerOverlay = true
                }
            
            let selectedPlayers = [winner1, winner2, loser1, loser2]
            let available = recentPlayers.filter { !selectedPlayers.contains($0.name) }
            if !available.isEmpty {
                Menu {
                    ForEach(available, id: \.name) { player in
                        Button {
                            text.wrappedValue = player.name
                            if let next = nextStep(after: field.toStep) {
                                advanceTo(next)
                            }
                        } label: {
                            Text(player.name)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
    
    private func selectPlayer(_ name: String, from step: AddGameStep) {
        switch step {
        case .winner1: winner1 = name
        case .winner2: winner2 = name
        case .loser1: loser1 = name
        case .loser2: loser2 = name
        case .winnerScore, .loserScore: return
        }
        if let next = nextStep(after: step) {
            advanceTo(next)
        }
    }
    
    private func advanceTo(_ step: AddGameStep) {
        activeStep = step
        switch step {
        case .winner1:
            focusedField = .winner1
            showPlayerOverlay = true
        case .winner2:
            focusedField = .winner2
            showPlayerOverlay = true
        case .loser1:
            focusedField = .loser1
            showPlayerOverlay = true
        case .loser2:
            focusedField = .loser2
            showPlayerOverlay = true
        case .winnerScore, .loserScore:
            focusedField = nil
            showPlayerOverlay = false
        }
    }
    
    private func assignPlayer(_ name: String, to field1: PlayerField, or field2: PlayerField,
                              player1: Binding<String>, player2: Binding<String>) {
        if player1.wrappedValue.isEmpty {
            player1.wrappedValue = name
            switch field1 {
            case .winner1: advanceTo(.winner2)
            case .winner2: advanceTo(.loser1)
            case .loser1: advanceTo(.loser2)
            case .loser2: advanceTo(.winnerScore)
            }
        } else if player2.wrappedValue.isEmpty {
            player2.wrappedValue = name
            switch field2 {
            case .winner1: advanceTo(.winner2)
            case .winner2: advanceTo(.loser1)
            case .loser1: advanceTo(.loser2)
            case .loser2: advanceTo(.winnerScore)
            }
        }
    }
    
    private func loadPlayers() {
        DatabaseManager.shared.fetchRecentPlayers(limit: 15) { [self] recent in
            recentPlayers = recent
        }
        DatabaseManager.shared.fetchAllPlayers { [self] all in
            allPlayers = all
        }
    }
    
    private func saveGame() {
        let w1 = winner1.trimmingCharacters(in: .whitespaces)
        let w2 = winner2.trimmingCharacters(in: .whitespaces)
        let l1 = loser1.trimmingCharacters(in: .whitespaces)
        let l2 = loser2.trimmingCharacters(in: .whitespaces)
        
        if let game = gameToEdit {
            DatabaseManager.shared.updateGame(id: game.id, recordName: game.recordName, winner1: w1, winner2: w2, winnerScore: winnerScore, loser1: l1, loser2: l2, loserScore: loserScore) { success in
                if success {
                    onSave?()
                    dismiss()
                }
            }
        } else {
            DatabaseManager.shared.insertGame(winner1: w1, winner2: w2, winnerScore: winnerScore, loser1: l1, loser2: l2, loserScore: loserScore) { success in
                if success {
                    onSave?()
                    dismiss()
                }
            }
        }
    }
}

// MARK: - AddGameStep helpers

extension AddGameView.AddGameStep {
    var isPlayerStep: Bool {
        switch self {
        case .winner1, .winner2, .loser1, .loser2: return true
        case .winnerScore, .loserScore: return false
        }
    }
    
    var playerField: AddGameView.PlayerField? {
        switch self {
        case .winner1: return .winner1
        case .winner2: return .winner2
        case .loser1: return .loser1
        case .loser2: return .loser2
        case .winnerScore, .loserScore: return nil
        }
    }
    
    var placeholderTitle: String {
        switch self {
        case .winner1: return "Winner 1"
        case .winner2: return "Winner 2"
        case .loser1: return "Loser 1"
        case .loser2: return "Loser 2"
        case .winnerScore, .loserScore: return ""
        }
    }
}

extension AddGameView.PlayerField {
    var toStep: AddGameView.AddGameStep {
        switch self {
        case .winner1: return .winner1
        case .winner2: return .winner2
        case .loser1: return .loser1
        case .loser2: return .loser2
        }
    }
}

#Preview {
    AddGameView()
}
