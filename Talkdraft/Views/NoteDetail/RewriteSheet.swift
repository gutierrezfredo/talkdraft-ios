import SwiftUI

// MARK: - Recent Presets

struct RecentPreset: Codable, Identifiable {
    let id: UUID
    var instructions: String
    var pinned: Bool
    var usedAt: Date

    init(instructions: String) {
        self.id = UUID()
        self.instructions = instructions
        self.pinned = false
        self.usedAt = Date()
    }
}

enum RecentPresetsStore {
    private static let key = "recentRewritePresets"
    private static let maxRecents = 8

    static var all: [RecentPreset] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([RecentPreset].self, from: data)) ?? []
    }

    static func add(instructions: String) {
        var presets = all
        // Don't duplicate — just bump to top
        presets.removeAll { $0.instructions == instructions }
        presets.insert(RecentPreset(instructions: instructions), at: 0)
        // Keep pinned + cap unpinned at maxRecents
        let pinned = presets.filter(\.pinned)
        let unpinned = presets.filter { !$0.pinned }.prefix(maxRecents)
        save(pinned + unpinned)
    }

    static func togglePin(id: UUID) {
        var presets = all
        guard let i = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[i].pinned.toggle()
        save(presets)
    }

    static func remove(id: UUID) {
        var presets = all
        presets.removeAll { $0.id == id }
        save(presets)
    }

    private static func save(_ presets: [RecentPreset]) {
        UserDefaults.standard.set(try? JSONEncoder().encode(presets), forKey: key)
    }
}

// MARK: - Rewrite Sheet

private struct RewriteTone: Identifiable {
    let id: String
    let label: String
    let emoji: String
    let description: String
}

private struct RewriteFormat: Identifiable {
    let id: String
    let label: String
    let emoji: String
    let color: Color
    let tones: [RewriteTone]
}

private let rewriteFormats: [RewriteFormat] = [
    RewriteFormat(id: "text-editing", label: "Text Editing", emoji: "✏️", color: .blue, tones: [
        RewriteTone(id: "edit-grammar", label: "Grammar", emoji: "✨", description: "Fix grammar, punctuation, and flow"),
        RewriteTone(id: "edit-shorter", label: "Shorter", emoji: "⚡", description: "Reduce length, keep the meaning"),
        RewriteTone(id: "edit-list", label: "List", emoji: "📋", description: "Convert into bullet points"),
        RewriteTone(id: "extract-actions", label: "Action Items", emoji: "✅", description: "Pull out tasks as checkboxes"),
    ]),
    RewriteFormat(id: "work", label: "Work", emoji: "💼", color: .orange, tones: [
        RewriteTone(id: "work-brainstorm", label: "Brainstorming", emoji: "💡", description: "Group and organize ideas"),
        RewriteTone(id: "work-progress", label: "Progress Report", emoji: "📊", description: "Done, status, and next steps"),
        RewriteTone(id: "work-slides", label: "Presentation Slides", emoji: "🖥️", description: "Slide titles with bullet points"),
        RewriteTone(id: "work-speech", label: "Speech Outline", emoji: "🎤", description: "Hook, key points, and closing"),
        RewriteTone(id: "work-linkedin-msg", label: "LinkedIn Message", emoji: "💬", description: "Brief connection message"),
    ]),
    RewriteFormat(id: "summary", label: "Summary", emoji: "📄", color: .yellow, tones: [
        RewriteTone(id: "summary-detailed", label: "Detailed Summary", emoji: "📖", description: "All key points and context"),
        RewriteTone(id: "summary-short", label: "Short Summary", emoji: "⚡", description: "Essential points in 2-3 sentences"),
        RewriteTone(id: "summary-meeting", label: "Meeting Takeaways", emoji: "🤝", description: "Decisions, actions, follow-ups"),
    ]),
    RewriteFormat(id: "style", label: "Writing Style", emoji: "🎨", color: .pink, tones: [
        RewriteTone(id: "style-casual", label: "Casual", emoji: "😎", description: "Relaxed, like texting a friend"),
        RewriteTone(id: "style-friendly", label: "Friendly", emoji: "😊", description: "Warm and approachable"),
        RewriteTone(id: "style-confident", label: "Confident", emoji: "💪", description: "Bold and assertive"),
        RewriteTone(id: "style-professional", label: "Professional", emoji: "💼", description: "Polished and work-ready"),
    ]),
    RewriteFormat(id: "emails", label: "Emails", emoji: "📧", color: .cyan, tones: [
        RewriteTone(id: "email-casual", label: "Casual Email", emoji: "😎", description: "Compose an informal email"),
        RewriteTone(id: "email-formal", label: "Formal Email", emoji: "👔", description: "Compose a professional email"),
    ]),
    RewriteFormat(id: "content", label: "Content Creation", emoji: "📱", color: .purple, tones: [
        RewriteTone(id: "content-blog", label: "Blog Post", emoji: "📝", description: "Intro, body, and conclusion"),
        RewriteTone(id: "content-facebook", label: "Facebook Post", emoji: "👍", description: "Conversational and engaging"),
        RewriteTone(id: "content-linkedin", label: "LinkedIn Post", emoji: "💼", description: "Professional with a takeaway"),
        RewriteTone(id: "content-instagram", label: "Instagram Post", emoji: "📸", description: "Punchy caption with line breaks"),
        RewriteTone(id: "content-x-post", label: "X Post", emoji: "𝕏", description: "Under 280 characters"),
        RewriteTone(id: "content-x-thread", label: "X Thread", emoji: "🧵", description: "Numbered tweets, each under 280"),
        RewriteTone(id: "content-video-script", label: "Video Script", emoji: "🎬", description: "Hook, sections, and CTA"),
        RewriteTone(id: "content-newsletter", label: "Newsletter", emoji: "📰", description: "Engaging intro and sign-off"),
    ]),
    RewriteFormat(id: "personal", label: "Personal", emoji: "🏠", color: .green, tones: [
        RewriteTone(id: "personal-grocery", label: "Grocery List", emoji: "🛒", description: "Extract items, group by category"),
        RewriteTone(id: "personal-meal", label: "Meal Planner", emoji: "🍽️", description: "Organize meals with ingredients"),
        RewriteTone(id: "personal-study", label: "Study Notes", emoji: "📚", description: "Headings, bullets, key concepts"),
    ]),
    RewriteFormat(id: "journaling", label: "Journaling", emoji: "📓", color: .indigo, tones: [
        RewriteTone(id: "journal-entry", label: "Journal Entry", emoji: "✍️", description: "Reflective and introspective"),
        RewriteTone(id: "journal-gratitude", label: "Gratitude", emoji: "🙏", description: "Focus on what to be thankful for"),
        RewriteTone(id: "journal-therapy", label: "Therapy Notes", emoji: "🧠", description: "Polish session notes, preserve raw thoughts"),
    ]),
]

struct RewriteSheet: View {
    /// (toneId, instructions, toneLabel, toneEmoji)
    let onSelect: (String?, String?, String?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedTab = 0
    @State private var customInstructions = ""
    @State private var searchText = ""
    @State private var keyboardVisible = false
    @State private var recentPresets: [RecentPreset] = RecentPresetsStore.all
    @AppStorage("rewriteFavorites") private var favoritesData = Data()
    @FocusState private var customFocused: Bool

    private var favoriteIds: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: favoritesData)) ?? []
    }

    private func toggleFavorite(_ toneId: String) {
        var ids = favoriteIds
        if ids.contains(toneId) {
            ids.remove(toneId)
        } else {
            ids.insert(toneId)
        }
        favoritesData = (try? JSONEncoder().encode(ids)) ?? Data()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Presets").tag(0)
                    Text("Custom").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .animation(.snappy, value: selectedTab)
                .onChange(of: selectedTab) {
                    customFocused = false
                }

                if selectedTab == 0 {
                    presetsView
                } else {
                    customView
                }
            }
            .navigationTitle("Rewrite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .interactiveDismissDisabled(keyboardVisible)
        .onAppear { recentPresets = RecentPresetsStore.all }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    // MARK: - Presets

    private var filteredFormats: [(format: RewriteFormat, tones: [RewriteTone])] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else {
            return rewriteFormats.map { ($0, $0.tones) }
        }
        return rewriteFormats.compactMap { format in
            let formatScore = matchScore(format.label, query: query)
            let matched = format.tones
                .filter {
                    matchScore($0.label, query: query) >= 0 ||
                    matchScore($0.description, query: query) >= 0 ||
                    formatScore >= 0
                }
                .sorted {
                    max(matchScore($0.label, query: query), matchScore($0.description, query: query)) >
                    max(matchScore($1.label, query: query), matchScore($1.description, query: query))
                }
            return matched.isEmpty ? nil : (format, matched)
        }
    }

    /// Returns 2 for word-start match, 1 for mid-word match, -1 for no match.
    private func matchScore(_ text: String, query: String) -> Int {
        let lower = text.lowercased()
        guard lower.contains(query) else { return -1 }
        if lower.hasPrefix(query) { return 2 }
        // Word-boundary: appears after a space or punctuation
        let pattern = "[^a-z]" + NSRegularExpression.escapedPattern(for: query)
        if (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)) != nil {
            return 2
        }
        return 1
    }

    private func highlighted(_ text: String) -> AttributedString {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        var attributed = AttributedString(text)
        guard !query.isEmpty else { return attributed }
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex {
            guard let range = attributed[searchStart...].range(of: query, options: .caseInsensitive) else { break }
            attributed[range].backgroundColor = Color.yellow.opacity(0.4)
            searchStart = range.upperBound
        }
        return attributed
    }

    private var filteredFavoriteTones: [(tone: RewriteTone, color: Color)] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return favoriteTones }
        return favoriteTones.filter {
            matchScore($0.tone.label, query: query) >= 0 ||
            matchScore($0.tone.description, query: query) >= 0
        }
    }

    private var filteredRecentPresets: [RecentPreset] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return recentPresets }
        return recentPresets.filter { $0.instructions.lowercased().contains(query) }
    }

    private var favoriteTones: [(tone: RewriteTone, color: Color)] {
        let ids = favoriteIds
        guard !ids.isEmpty else { return [] }
        var result: [(RewriteTone, Color)] = []
        for format in rewriteFormats {
            for tone in format.tones where ids.contains(tone.id) {
                result.append((tone, format.color))
            }
        }
        return result
    }

    private var isPresetsEmpty: Bool {
        filteredRecentPresets.isEmpty && filteredFavoriteTones.isEmpty && filteredFormats.isEmpty
    }

    private var presetsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if isPresetsEmpty {
                    VStack(spacing: 12) {
                        Image("search-empty")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 60)
                            .foregroundStyle(.secondary)
                        Text("No results")
                            .font(.headline)
                        Text("No presets matching \"\(searchText.trimmingCharacters(in: .whitespaces))\".")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .padding(.horizontal, 24)
                }

                // Recent custom presets
                if !filteredRecentPresets.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text("🕐")
                            Text("RECENT CUSTOMS")
                        }
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                        recentPresetsGrid
                            .padding(.horizontal, 20)
                    }
                }

                // Favorites section
                if !filteredFavoriteTones.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text("⭐")
                            Text("FAVORITES")
                        }
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                        favoritesGrid
                            .padding(.horizontal, 20)
                    }
                }

                ForEach(filteredFormats, id: \.format.id) { item in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Text(item.format.emoji)
                            Text(item.format.label.uppercased())
                        }
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)

                        toneGrid(for: item.tones, color: item.format.color)
                            .padding(.horizontal, 20)
                    }
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .searchable(text: $searchText, prompt: "Search presets")
    }

    private var recentPresetsGrid: some View {
        let items = filteredRecentPresets
        let rowCount = (items.count + 1) / 2
        return VStack(spacing: 12) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 12) {
                    recentPresetCard(items[row * 2])
                    if row * 2 + 1 < items.count {
                        recentPresetCard(items[row * 2 + 1])
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private func recentPresetCard(_ preset: RecentPreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🕐")
                .font(.title2)

            Text(highlighted(preset.instructions))
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .overlay(alignment: .topTrailing) {
            if preset.pinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: preset.pinned)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.brand.opacity(colorScheme == .dark ? 0.12 : 0.1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(nil, preset.instructions, nil, nil)
            dismiss()
        }
        .contextMenu {
            Button {
                RecentPresetsStore.togglePin(id: preset.id)
                recentPresets = RecentPresetsStore.all
            } label: {
                Label(preset.pinned ? "Unpin" : "Pin", systemImage: preset.pinned ? "pin.slash" : "pin")
            }
            Button(role: .destructive) {
                RecentPresetsStore.remove(id: preset.id)
                recentPresets = RecentPresetsStore.all
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var favoritesGrid: some View {
        let items = filteredFavoriteTones
        let rowCount = (items.count + 1) / 2
        return VStack(spacing: 12) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 12) {
                    toneCard(items[row * 2].tone, color: items[row * 2].color)
                    if row * 2 + 1 < items.count {
                        toneCard(items[row * 2 + 1].tone, color: items[row * 2 + 1].color)
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private func toneGrid(for tones: [RewriteTone], color: Color) -> some View {
        let rowCount = (tones.count + 1) / 2
        return VStack(spacing: 12) {
            ForEach(0..<rowCount, id: \.self) { row in
                HStack(spacing: 12) {
                    toneCard(tones[row * 2], color: color)
                    if row * 2 + 1 < tones.count {
                        toneCard(tones[row * 2 + 1], color: color)
                    } else {
                        Color.clear
                    }
                }
            }
        }
    }

    private func toneCard(_ tone: RewriteTone, color: Color) -> some View {
        let isFavorite = favoriteIds.contains(tone.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(tone.emoji)
                .font(.title2)

            Text(highlighted(tone.label))
                .font(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Text(highlighted(tone.description))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .overlay(alignment: .topTrailing) {
            if isFavorite {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .padding(8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.3, bounce: 0.4), value: isFavorite)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(color.opacity(colorScheme == .dark ? 0.12 : 0.1))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect(tone.id, nil, tone.label, tone.emoji)
            dismiss()
        }
        .onLongPressGesture {
            toggleFavorite(tone.id)
        }
    }

    // MARK: - Custom

    private var customView: some View {
        VStack(spacing: 20) {
            TextField("e.g. Make it sound like a TED talk", text: $customInstructions, axis: .vertical)
                .font(.body)
                .lineLimit(3...8)
                .focused($customFocused)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.darkSurface : .white.opacity(0.7))
                )
                .padding(.horizontal, 20)

            Button {
                onSelect(nil, customInstructions.trimmingCharacters(in: .whitespaces), nil, nil)
                dismiss()
            } label: {
                Text("Rewrite")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Capsule().fill(Color.brand))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
            .disabled(customInstructions.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(customInstructions.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)

            Spacer()
        }
        .padding(.top, 20)
    }
}
