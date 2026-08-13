import SwiftUI

struct AddGameView: View {
    @Environment(\.dismiss) private var dismiss

    var gameToEdit: LegacyGame? = nil
    var statsSource: StatsSource = .myDatabase
    var cloudDbId: String? = nil
    /// Database ID of the editor (for activity log). Usually DatabaseOwnerManager.shared.myDbId.
    var editorDbId: String? = nil
    var isOnline: Bool = true
    var onSave: (() -> Void)?
    var onSaveToLocal: ((LegacyGame) -> Void)?
    /// When set, used instead of Environment dismiss (e.g. when embedded in a tab).
    var onDismiss: (() -> Void)? = nil

    private func performDismiss() {
        if let onDismiss = onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

    /// Clears form fields after successfully adding a new game so the tab shows a fresh form next time.
    private func clearFormIfNewGame() {
        guard gameToEdit == nil else { return }
        winner1 = ""
        winner2 = ""
        loser1 = ""
        loser2 = ""
        winnerScore = nil
        loserScore = nil
        comment = ""
        activeStep = nil
        showPlayerOverlay = false
        saveError = nil
    }

    /// On successful save: if adding a new game from the tab, stay and show success; otherwise dismiss.
    private func handleSaveSuccess() {
        onSave?()
        clearFormIfNewGame()
        if gameToEdit == nil, onDismiss != nil {
            showAddSuccess = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                showAddSuccess = false
            }
        } else {
            performDismiss()
        }
    }

    // Players
    @State private var winner1: String
    @State private var winner2: String
    @State private var loser1: String
    @State private var loser2: String
    
    // Scores
    @State private var winnerScore: Int?
    @State private var loserScore: Int?

    @State private var comment: String = ""

    // Autocomplete (database players only)
    @State private var allPlayers: [PlayerInfo] = []
    @State private var recentPlayers: [PlayerInfo] = []
    @State private var activeStep: AddGameStep?
    @State private var showPlayerOverlay = false
    @FocusState private var focusedField: PlayerField?
    @FocusState private var focusedScoreField: AddGameStep?
    @FocusState private var isCommentFocused: Bool
    @State private var isSaving = false
    @State private var saveError: String?
    @State private var showAddSuccess = false

    // Common scores from the database
    private let commonWinnerScores = [21, 22, 23, 24, 25, 15]
    /// Loser score options. When winner > 21, only (winner - 2) is allowed; otherwise winner-2 down to 0.
    private var commonLoserScores: [Int] {
        guard let w = winnerScore else { return [] }
        if w > 21 {
            return [w - 2]
        }
        let start = max(0, w - 2)
        return stride(from: start, through: 0, by: -1).map { $0 }
    }
    
    init(gameToEdit: LegacyGame? = nil, statsSource: StatsSource = .myDatabase, cloudDbId: String? = nil, editorDbId: String? = nil, isOnline: Bool = true, onSave: (() -> Void)? = nil, onSaveToLocal: ((LegacyGame) -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.gameToEdit = gameToEdit
        self.statsSource = statsSource
        self.cloudDbId = cloudDbId
        self.editorDbId = editorDbId
        self.isOnline = isOnline
        self.onSave = onSave
        self.onSaveToLocal = onSaveToLocal
        self.onDismiss = onDismiss
        if let g = gameToEdit {
            _winner1 = State(initialValue: g.winner1)
            _winner2 = State(initialValue: g.winner2)
            _loser1 = State(initialValue: g.loser1)
            _loser2 = State(initialValue: g.loser2)
            _winnerScore = State(initialValue: Optional(g.winnerScore))
            _loserScore = State(initialValue: Optional(g.loserScore))
            _comment = State(initialValue: g.comment)
        } else {
            _winner1 = State(initialValue: "")
            _winner2 = State(initialValue: "")
            _loser1 = State(initialValue: "")
            _loser2 = State(initialValue: "")
            _winnerScore = State(initialValue: nil)
            _loserScore = State(initialValue: nil)
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

    private func step(for field: PlayerField) -> AddGameStep {
        switch field {
        case .winner1: return .winner1
        case .winner2: return .winner2
        case .loser1: return .loser1
        case .loser2: return .loser2
        }
    }
    
    private var isValid: Bool {
        guard !winner1.trimmingCharacters(in: .whitespaces).isEmpty,
              !winner2.trimmingCharacters(in: .whitespaces).isEmpty,
              !loser1.trimmingCharacters(in: .whitespaces).isEmpty,
              !loser2.trimmingCharacters(in: .whitespaces).isEmpty,
              let w = winnerScore, let l = loserScore else { return false }
        if w > 21 {
            return l == w - 2
        }
        return w > l
    }
    
    private func searchPlayers(_ searchText: String) -> [PlayerInfo] {
        if searchText.isEmpty { return recentPlayers }
        let lowercased = searchText.lowercased()
        return allPlayers.filter { $0.name.lowercased().contains(lowercased) }
            .prefix(12)
            .map { $0 }
    }
    
    private var addGameNavigationTitle: String {
        gameToEdit == nil ? "Add Game" : "Edit Game"
    }

    private var saveErrorAlertBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { if !$0 { saveError = nil } }
        )
    }

    var body: some View {
        NavigationStack {
            addGameBodyContent
                .navigationTitle(addGameNavigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { performDismiss() }
                            .foregroundStyle(Color(red: 1, green: 0.45, blue: 0.3))
                    }
                }
                .onAppear(perform: addGameOnAppear)
                .onChange(of: winnerScore, addGameOnWinnerScoreChange)
                .onChange(of: focusedScoreField, addGameOnFocusedScoreFieldChange)
                .alert("Save Failed", isPresented: saveErrorAlertBinding) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(saveError ?? "")
                }
        }
    }

    private func addGameOnWinnerScoreChange(_ old: Int?, _ newWinner: Int?) {
        if let w = newWinner, w > 21 {
            loserScore = w - 2
        }
    }

    private func addGameOnFocusedScoreFieldChange(_ old: AddGameStep?, _ newStep: AddGameStep?) {
        guard let newStep = newStep else { return }
        if newStep == .winnerScore || newStep == .loserScore {
            activeStep = newStep
            focusedField = nil
        }
    }

    private var addGameBodyContent: some View {
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

            ScrollViewReader { scrollProxy in
                ScrollView {
                    addGameFormContent
                        .padding(20)
                        .padding(.bottom, isCommentFocused ? 280 : 40)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: isCommentFocused) { _, focused in
                    if focused {
                        withAnimation(.easeOut(duration: 0.25)) {
                            scrollProxy.scrollTo("submitButtons", anchor: .bottom)
                        }
                    }
                }
            }

            if showAddSuccess {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(.white)
                        Text("Game added successfully")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(Capsule().fill(Color.green.opacity(0.9)))
                    .padding(.top, 12)
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .animation(.easeOut(duration: 0.25), value: showAddSuccess)
            }
        }
    }

    private func addGameOnAppear() {
        loadPlayers()
        if let w = winnerScore, w > 21, loserScore != w - 2 {
            loserScore = w - 2
        }
        if gameToEdit == nil {
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                await MainActor.run {
                    advanceTo(.winner1)
                }
            }
        }
    }
    
    private var addGameFormContent: some View {
        VStack(spacing: 12) {
            addGamePlayerRow(label: "Winner 1", text: $winner1, field: .winner1, focusedField: $focusedField)
            addGameInlinePlayerList(field: .winner1, focusedField: focusedField, playerBinding: $winner1)
            
            addGamePlayerRow(label: "Winner 2", text: $winner2, field: .winner2, focusedField: $focusedField)
            addGameInlinePlayerList(field: .winner2, focusedField: focusedField, playerBinding: $winner2)
            
            addGamePlayerRow(label: "Loser 1", text: $loser1, field: .loser1, focusedField: $focusedField)
            addGameInlinePlayerList(field: .loser1, focusedField: focusedField, playerBinding: $loser1)
            
            addGamePlayerRow(label: "Loser 2", text: $loser2, field: .loser2, focusedField: $focusedField)
            addGameInlinePlayerList(field: .loser2, focusedField: focusedField, playerBinding: $loser2)
            
            addGameScoreRow(label: "Winners' Score", value: $winnerScore, step: .winnerScore, focusedScoreField: $focusedScoreField)
            addGameInlineScoreList(step: .winnerScore, scores: commonWinnerScores, selected: winnerScore) { s in
                winnerScore = s
                if s > 21 { loserScore = s - 2 }
                activeStep = gameToEdit == nil ? .loserScore : nil
                focusedScoreField = nil
            }
            
            addGameScoreRow(label: "Losers' Score", value: $loserScore, step: .loserScore, focusedScoreField: $focusedScoreField)
            addGameInlineScoreList(step: .loserScore, scores: commonLoserScores, selected: loserScore) { s in
                loserScore = s
                activeStep = nil
                focusedScoreField = nil
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text("Comments (optional)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
                addGameCommentField(comment: $comment, isCommentFocused: $isCommentFocused)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            submitButtonsSection
        }
    }

    private var submitButtonsSection: some View {
        VStack(spacing: 12) {
            Button {
                saveGame()
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text("Submit")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.35, green: 0.7, blue: 1)))
            }
            .disabled(!isValid || isSaving)

            Button {
                winner1 = ""
                winner2 = ""
                loser1 = ""
                loser2 = ""
                winnerScore = nil
                loserScore = nil
                comment = ""
                activeStep = nil
                showPlayerOverlay = false
                focusedField = nil
                focusedScoreField = nil
                isCommentFocused = false
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                    Text("Clear form")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .id("submitButtons")
    }

    private func fullScreenPlayerOverlay(step: AddGameStep) -> some View {
        let suggestions = typingMenuSuggestions(for: step)
        return
            VStack(spacing: 0) {
                // Header with centered title and actions on the right
                ZStack(alignment: .center) {
                    Text(step.placeholderTitle)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                    HStack {
                        Spacer()
                        Button {
                            showPlayerOverlay = false
                            focusedField = step.playerField
                        } label: {
                            Label("Type name", systemImage: "keyboard")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
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
                }
                .padding(.vertical, 20)
                .background(Color(red: 0.08, green: 0.12, blue: 0.18))
                
                Divider().background(Color.white.opacity(0.2))
                
                // Scrollable grid of players
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(suggestions.prefix(50)) { player in
                            Button {
                                selectPlayer(player.name, from: step)
                            } label: {
                                HStack {
                                    Text(player.name)
                                        .font(.system(size: 19, weight: .medium, design: .rounded))
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(player.gameCount)")
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.7))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 16)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.2))
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
    
    /// Names already selected in fields other than the given step (trimmed, non-empty).
    private func namesInOtherFields(than step: AddGameStep) -> Set<String> {
        let w1 = winner1.trimmingCharacters(in: .whitespaces)
        let w2 = winner2.trimmingCharacters(in: .whitespaces)
        let l1 = loser1.trimmingCharacters(in: .whitespaces)
        let l2 = loser2.trimmingCharacters(in: .whitespaces)
        let all = [w1, w2, l1, l2].filter { !$0.isEmpty }
        let current: String
        switch step {
        case .winner1: current = w1
        case .winner2: current = w2
        case .loser1: current = l1
        case .loser2: current = l2
        case .winnerScore, .loserScore: return Set(all)
        }
        return Set(all).subtracting([current])
    }
    
    /// Current text in the active player field (for filtering suggestions).
    private func currentText(for step: AddGameStep) -> String {
        switch step {
        case .winner1: return winner1.trimmingCharacters(in: .whitespaces)
        case .winner2: return winner2.trimmingCharacters(in: .whitespaces)
        case .loser1: return loser1.trimmingCharacters(in: .whitespaces)
        case .loser2: return loser2.trimmingCharacters(in: .whitespaces)
        case .winnerScore, .loserScore: return ""
        }
    }

    /// Suggestions for the player overlay: DB players (recent + all) not in other fields; filtered by current field text.
    private func stepSuggestions(for step: AddGameStep) -> [PlayerInfo] {
        switch step {
        case .winnerScore, .loserScore: return []
        default: break
        }
        let other = namesInOtherFields(than: step)
        let recent = recentPlayers.filter { !other.contains($0.name) }
        let allFiltered = allPlayers.filter { !other.contains($0.name) }
        let recentNames = Set(recent.map(\.name))
        let rest = allFiltered.filter { !recentNames.contains($0.name) }
        let combined = recent + rest
        let text = currentText(for: step)
        guard !text.isEmpty else { return combined }
        return combined.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    /// Suggestions for the inline typing menu: when field empty → only recent players; when typing → DB players filtered by text.
    private func typingMenuSuggestions(for step: AddGameStep) -> [PlayerInfo] {
        let text = currentText(for: step)
        if text.isEmpty {
            let other = namesInOtherFields(than: step)
            return recentPlayers.filter { !other.contains($0.name) }
        }
        return stepSuggestions(for: step)
    }
    
    private func fullScreenScoreOverlay(
        title: String,
        scores: [Int],
        color: Color,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .center) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                HStack {
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
            }
            .padding(.vertical, 20)
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
    
    private let addGameRowInactiveBg = Color.white.opacity(0.2)
    private let addGameRowActiveBorder = Color(red: 0.35, green: 0.7, blue: 1)
    private let addGameRowFontSize: CGFloat = 19
    private let addGameRowPlaceholderOpacity: Double = 0.95
    
    @ViewBuilder
    private func addGamePlayerRow(
        label: String,
        text: Binding<String>,
        field: PlayerField,
        focusedField: FocusState<PlayerField?>.Binding
    ) -> some View {
        let isFocused = focusedField.wrappedValue == field
        ZStack(alignment: .trailing) {
            ZStack {
                TextField("", text: text)
                    .font(.system(size: addGameRowFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .background(addGameRowInactiveBg)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isFocused ? addGameRowActiveBorder : Color.clear, lineWidth: 2.5)
                    )
                    .focused(focusedField, equals: field)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .onSubmit {
                        if gameToEdit != nil {
                            focusedField.wrappedValue = nil
                        } else if let next = nextStep(after: field.toStep) {
                            advanceTo(next)
                        }
                    }
                    .onChange(of: text.wrappedValue) { _, _ in
                        if activeStep == nil || activeStep?.playerField == field {
                            activeStep = field.toStep
                        }
                    }
                if text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(label)
                        .font(.system(size: addGameRowFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(addGameRowPlaceholderOpacity))
                        .multilineTextAlignment(.center)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            if !text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.75))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func addGameScoreRow(label: String, value: Binding<Int?>, step: AddGameStep, focusedScoreField: FocusState<AddGameStep?>.Binding) -> some View {
        let isFocused = focusedScoreField.wrappedValue == step
        let scoreString = Binding(
            get: { value.wrappedValue.map { "\($0)" } ?? "" },
            set: { new in
                let digits = new.filter { $0.isNumber }
                if digits.isEmpty {
                    value.wrappedValue = nil
                } else if let n = Int(digits), n >= 0, n <= 99 {
                    value.wrappedValue = n
                }
            }
        )
        ZStack(alignment: .trailing) {
            TextField(label, text: scoreString)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .keyboardType(.numbersAndPunctuation)
                .submitLabel(step == .loserScore ? .done : .next)
                .onSubmit {
                    if step == .winnerScore {
                        focusedScoreField.wrappedValue = .loserScore
                    } else {
                        focusedScoreField.wrappedValue = nil
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .background(addGameRowInactiveBg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isFocused ? addGameRowActiveBorder : Color.clear, lineWidth: 2)
                )
                .focused(focusedScoreField, equals: step)
            if value.wrappedValue != nil {
                Button {
                    value.wrappedValue = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    @ViewBuilder
    private func addGameCommentField(comment: Binding<String>, isCommentFocused: FocusState<Bool>.Binding) -> some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("Add a note...", text: comment, axis: .vertical)
                .lineLimit(2...4)
                .textInputAutocapitalization(.sentences)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .padding(14)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(.white)
                .focused(isCommentFocused)
            if !comment.wrappedValue.isEmpty {
                Button {
                    comment.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
            }
        }
    }
    
    @ViewBuilder
    private func addGameInlinePlayerList(
        field: PlayerField,
        focusedField: PlayerField?,
        playerBinding: Binding<String>
    ) -> some View {
        if focusedField == field, !typingMenuSuggestions(for: step(for: field)).isEmpty {
            addGameInlinePlayerListContent(field: field, playerBinding: playerBinding)
        }
    }
    
    private func addGameInlinePlayerListContent(field: PlayerField, playerBinding: Binding<String>) -> some View {
        let step = step(for: field)
        let list = Array(typingMenuSuggestions(for: step).prefix(20))
        return ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.element.name) { index, player in
                    Button {
                        playerBinding.wrappedValue = player.name
                        if gameToEdit == nil, let next = nextStep(after: step) {
                            advanceTo(next)
                        }
                    } label: {
                        Text(player.name)
                            .font(.system(size: 19, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < list.count - 1 {
                        Divider().background(Color.white.opacity(0.35))
                    }
                }
            }
        }
        .background(Color(red: 0.1, green: 0.12, blue: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .frame(maxHeight: 280)
    }
    
    @ViewBuilder
    private func addGameInlineScoreList(
        step: AddGameStep,
        scores: [Int],
        selected: Int?,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        if activeStep == step {
            VStack(spacing: 0) {
                ForEach(Array(scores.enumerated()), id: \.element) { index, s in
                    Button {
                        onSelect(s)
                    } label: {
                        Text("\(s)")
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < scores.count - 1 {
                        Divider().background(Color.white.opacity(0.15))
                    }
                }
            }
            .background(Color(red: 0.08, green: 0.1, blue: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
    
    @ViewBuilder
    private func teamSection(
        title: String,
        color: Color,
        player1: Binding<String>,
        player2: Binding<String>,
        player1Field: PlayerField,
        player2Field: PlayerField,
        player1StepOnReturn: AddGameStep,
        player2StepOnReturn: AddGameStep,
        score: Binding<Int>,
        commonScores: [Int],
        scoreStep: AddGameStep?,
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
            
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    playerField(text: player1, field: player1Field, stepOnReturn: player1StepOnReturn, focusedField: focusedField)
                    playerField(text: player2, field: player2Field, stepOnReturn: player2StepOnReturn, focusedField: focusedField)
                }
                
                typingAutocompleteMenu(
                    focusedField: focusedField,
                    player1Field: player1Field,
                    player2Field: player2Field,
                    player1: player1,
                    player2: player2,
                    color: color
                )
                
                let selectedPlayers = [winner1, winner2, loser1, loser2]
                let recentAvailable = recentPlayers.filter { !selectedPlayers.contains($0.name) }
                let restAvailable = allPlayers.filter { !selectedPlayers.contains($0.name) && !recentPlayers.map(\.name).contains($0.name) }
                let availablePlayers = (recentAvailable + restAvailable).prefix(6)
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
                
                // Score: tap to open full-screen picker, or tap a chip to set inline
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
                .contentShape(Rectangle())
                .onTapGesture {
                    if let step = scoreStep {
                        activeStep = step
                    }
                }
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
    private func typingAutocompleteMenu(
        focusedField: FocusState<PlayerField?>.Binding,
        player1Field: PlayerField,
        player2Field: PlayerField,
        player1: Binding<String>,
        player2: Binding<String>,
        color: Color
    ) -> some View {
        if let focused = focusedField.wrappedValue, focused == player1Field || focused == player2Field {
            let step = step(for: focused)
            let text = currentText(for: step)
            let suggestions = typingMenuSuggestions(for: step).prefix(text.isEmpty ? 8 : 14)
            if !suggestions.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(suggestions), id: \.name) { player in
                            Button {
                                if focused == player1Field {
                                    player1.wrappedValue = player.name
                                } else {
                                    player2.wrappedValue = player.name
                                }
                                if gameToEdit == nil, let next = nextStep(after: step) {
                                    advanceTo(next)
                                }
                            } label: {
                                Text(player.name)
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 260)
                .background(Color.white.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    @ViewBuilder
    private func playerField(
        text: Binding<String>,
        field: PlayerField,
        stepOnReturn: AddGameStep,
        focusedField: FocusState<PlayerField?>.Binding
    ) -> some View {
        let placeholder = field == .winner1 || field == .winner2 ? "Player" : "Player"
        HStack(spacing: 6) {
            // Tap opens overlay (player list + "Type name" for keyboard); overlay takes tap priority over TextField
            ZStack(alignment: .leading) {
                TextField(placeholder, text: text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.next)
                    .focused(focusedField, equals: field)
                .onSubmit {
                    if gameToEdit != nil {
                        focusedField.wrappedValue = nil
                        activeStep = nil
                        showPlayerOverlay = false
                    } else {
                        advanceTo(stepOnReturn)
                    }
                }
                    .onChange(of: text.wrappedValue) { _, _ in
                        if activeStep == nil || activeStep?.playerField == field {
                            activeStep = field.toStep
                        }
                    }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        activeStep = field.toStep
                        showPlayerOverlay = true
                    }
            }
            
            let selectedPlayers = [winner1, winner2, loser1, loser2]
            let recentAvailable = recentPlayers.filter { !selectedPlayers.contains($0.name) }
            let restAvailable = allPlayers.filter { !selectedPlayers.contains($0.name) && !recentPlayers.map(\.name).contains($0.name) }
            let available = recentAvailable + restAvailable
            if !available.isEmpty {
                Menu {
                    ForEach(available, id: \.name) { player in
                        Button {
                            text.wrappedValue = player.name
                            if gameToEdit == nil, let next = nextStep(after: field.toStep) {
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
        if gameToEdit != nil {
            activeStep = nil
            showPlayerOverlay = false
            focusedField = nil
        } else if let next = nextStep(after: step) {
            advanceTo(next)
        }
    }
    
    private func advanceTo(_ step: AddGameStep) {
        activeStep = step
        switch step {
        case .winner1:
            focusedField = .winner1
            showPlayerOverlay = !typingMenuSuggestions(for: step).isEmpty
        case .winner2:
            focusedField = .winner2
            showPlayerOverlay = !typingMenuSuggestions(for: step).isEmpty
        case .loser1:
            focusedField = .loser1
            showPlayerOverlay = !typingMenuSuggestions(for: step).isEmpty
        case .loser2:
            focusedField = .loser2
            showPlayerOverlay = !typingMenuSuggestions(for: step).isEmpty
        case .winnerScore, .loserScore:
            focusedField = nil
            showPlayerOverlay = false
        }
    }
    
    private func assignPlayer(_ name: String, to field1: PlayerField, or field2: PlayerField,
                              player1: Binding<String>, player2: Binding<String>) {
        if player1.wrappedValue.isEmpty {
            player1.wrappedValue = name
            if gameToEdit == nil {
                switch field1 {
                case .winner1: advanceTo(.winner2)
                case .winner2: advanceTo(.loser1)
                case .loser1: advanceTo(.loser2)
                case .loser2: advanceTo(.winnerScore)
                }
            }
        } else if player2.wrappedValue.isEmpty {
            player2.wrappedValue = name
            if gameToEdit == nil {
                switch field2 {
                case .winner1: advanceTo(.winner2)
                case .winner2: advanceTo(.loser1)
                case .loser1: advanceTo(.loser2)
                case .loser2: advanceTo(.winnerScore)
                }
            }
        }
    }
    
    private var keyboardSuggestionsBarVisible: Bool {
        guard let field = focusedField else { return false }
        return !typingMenuSuggestions(for: step(for: field)).isEmpty
    }

    /// First 3 suggestions above the keyboard so the accessory bar shows useful content instead of empty space.
    @ViewBuilder
    private var keyboardSuggestionsBar: some View {
        if let field = focusedField {
            let step = step(for: field)
            let suggestions = Array(typingMenuSuggestions(for: step).prefix(3))
            if !suggestions.isEmpty {
                HStack(spacing: 8) {
                    ForEach(suggestions) { player in
                        Button {
                            switch field {
                            case .winner1: winner1 = player.name
                            case .winner2: winner2 = player.name
                            case .loser1: loser1 = player.name
                            case .loser2: loser2 = player.name
                            }
                            if gameToEdit == nil, let next = nextStep(after: step) {
                                advanceTo(next)
                            }
                        } label: {
                            Text(player.name)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        .foregroundStyle(.white)
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func loadPlayers() {
        guard let dbId = cloudDbId else {
            recentPlayers = []
            allPlayers = []
            return
        }
        // Use cache immediately so autocomplete is instant (order is by "last entered by current user")
        if let cached = cloud.cachedPlayers(dbId: dbId, editorDbId: editorDbId) {
            allPlayers = cached
            recentPlayers = Array(cached.prefix(15))
        } else {
            recentPlayers = []
            allPlayers = []
        }
        // Refresh from Firestore in background
        cloud.fetchAllPlayers(dbId: dbId, editorDbId: editorDbId) { [self] all in
            allPlayers = all
            recentPlayers = Array(all.prefix(15))
        }
    }

    /// Trim, collapse multiple spaces to one, and capitalize first letter of each word.
    private static func normalizedName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        return parts.map { part in
            guard !part.isEmpty else { return part }
            return part.prefix(1).uppercased() + part.dropFirst(1).lowercased()
        }.joined(separator: " ")
    }

    private func saveGame() {
        guard let wScore = winnerScore, let lScore = loserScore else { return }
        let w1 = Self.normalizedName(winner1)
        let w2 = Self.normalizedName(winner2)
        let l1 = Self.normalizedName(loser1)
        let l2 = Self.normalizedName(loser2)
        saveError = nil
        isSaving = true

        // Offline save to local cache (my database only)
        if cloudDbId != nil, !isOnline, let onSaveToLocal = onSaveToLocal {
            let recordName: String
            let date: Date
            let id: Int
            if let existing = gameToEdit {
                recordName = existing.recordName ?? "offline-\(UUID().uuidString)"
                date = existing.date
                id = existing.id
            } else {
                recordName = "offline-\(UUID().uuidString)"
                date = Date()
                id = abs(recordName.hashValue) & 0x7FFF_FFFF
            }
            let game = LegacyGame(id: id, date: date, winner1: w1, winner2: w2, winnerScore: wScore, loser1: l1, loser2: l2, loserScore: lScore, comment: comment, recordName: recordName)
            onSaveToLocal(game)
            isSaving = false
            handleSaveSuccess()
            return
        }

        if let dbId = cloudDbId {
            if let game = gameToEdit, let documentId = game.recordName, !documentId.hasPrefix("offline-") {
                cloud.updateGame(dbId: dbId, documentId: documentId, winner1: w1, winner2: w2, winnerScore: wScore, loser1: l1, loser2: l2, loserScore: lScore, comment: comment, editorDbId: editorDbId) { result in
                    isSaving = false
                    switch result {
                    case .success:
                        onSave?()
                        performDismiss()
                    case .failure(let error): saveError = error.localizedDescription
                    }
                }
            } else {
                let gameDate = Date()
                cloud.insertGame(dbId: dbId, date: gameDate, winner1: w1, winner2: w2, winnerScore: wScore, loser1: l1, loser2: l2, loserScore: lScore, comment: comment, editorDbId: editorDbId) { result in
                    isSaving = false
                    switch result {
                    case .success:
                        handleSaveSuccess()
                    case .failure(let error): saveError = error.localizedDescription
                    }
                }
            }
        } else {
            isSaving = false
            saveError = "No database selected."
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
    
    /// Title for the current step (including score steps); used for prominent header.
    var displayTitle: String {
        switch self {
        case .winner1: return "Winner 1"
        case .winner2: return "Winner 2"
        case .loser1: return "Loser 1"
        case .loser2: return "Loser 2"
        case .winnerScore: return "Winner score"
        case .loserScore: return "Loser score"
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
