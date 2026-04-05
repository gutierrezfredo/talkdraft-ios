import StoreKit
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(NoteStore.self) private var noteStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @State private var showDeleteConfirmation = false
    @State private var showSignOutConfirmation = false
    @State private var showCancelDeletion = false
    @State private var isDeletionLoading = false
    @State private var showAudioImporter = false
    @State private var showGuestPaywall = false
    @State private var showTrialReminderTest = false
    @State private var showWidgetDiscoveryTest = false
    @State private var importedNote: Note?

    #if DEBUG
    static let forceOnboardingKey = "debug.forceOnboardingFlow"
    private static let onboardingCompletedDeviceKey = "onboarding.completed.device"

    static func onboardingCompletedUserKey(for userId: UUID) -> String {
        "onboarding.completed.\(userId.uuidString)"
    }

    static func resetOnboardingState(
        userId: UUID?,
        forceOnboardingFlow: Bool,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(forceOnboardingFlow, forKey: forceOnboardingKey)
        defaults.removeObject(forKey: onboardingCompletedDeviceKey)
        if let userId {
            defaults.removeObject(forKey: onboardingCompletedUserKey(for: userId))
        }
    }
    #endif

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    private var cardColor: Color {
        colorScheme == .dark ? .darkSurface : .white
    }

    private var isGuestAtLimit: Bool {
        authStore.isGuest && noteStore.notes.count >= AuthStore.guestNoteLimit
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - Deletion Warning Banner

                if let deletionDate = authStore.user?.deletionScheduledAt {
                    Button {
                        showCancelDeletion = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title3)
                                .foregroundStyle(.red)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Account Deletion Scheduled")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)

                                Text("Permanently deleted on \(deletionDate.formatted(date: .abbreviated, time: .omitted)). Tap to cancel.")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.8))
                            }

                            Spacer()
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(.red.opacity(0.1))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .stroke(.red.opacity(0.2), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - General

                SettingsSection("General") {
                    NavigationLink {
                        CategoriesView()
                    } label: {
                        SettingsRow(
                            icon: "folder",
                            title: "Categories"
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    NavigationLink {
                        LanguagePickerView()
                    } label: {
                        SettingsRow(
                            icon: "globe",
                            title: "Recording Language",
                            value: languageDisplayName(settingsStore.language)
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    NavigationLink {
                        CustomDictionaryView()
                    } label: {
                        SettingsRow(
                            icon: "text.book.closed",
                            title: "Custom Dictionary",
                            value: settingsStore.customDictionary.isEmpty
                                ? nil
                                : "\(settingsStore.customDictionary.count) word\(settingsStore.customDictionary.count == 1 ? "" : "s")"
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 12) {
                        SettingsRow(
                            icon: "circle.lefthalf.filled",
                            title: "Appearance",
                            showChevron: false
                        )

                        ThemeInlinePicker()
                            .padding(.horizontal, 16)
                            .padding(.bottom, 16)
                    }
                }

                // MARK: - Tools

                SettingsSection("Tools") {
                    Button {
                        if isGuestAtLimit {
                            showGuestPaywall = true
                        } else {
                            showAudioImporter = true
                        }
                    } label: {
                        SettingsRow(
                            icon: "waveform.badge.plus",
                            title: "Import Audio",
                            showChevron: false
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    NavigationLink {
                        RecentlyDeletedView()
                    } label: {
                        SettingsRow(
                            icon: "trash",
                            title: "Recently Deleted",
                            value: noteStore.deletedNotes.isEmpty ? nil : "\(noteStore.deletedNotes.count)"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - Account

                SettingsSection("Account") {
                    Button {
                        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        SettingsRow(
                            icon: "creditcard",
                            title: "Manage Subscription",
                            value: subscriptionStore.isPro ? "Pro" : "Not subscribed"
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        requestReview()
                    } label: {
                        SettingsRow(
                            icon: "star.bubble",
                            title: "Rate Talkdraft",
                            showChevron: false
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        openSupportPage()
                    } label: {
                        SettingsRow(
                            icon: "envelope",
                            title: "Contact Support",
                            showChevron: false,
                            trailingIcon: "arrow.up.right"
                        )
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        openFeedbackEmail()
                    } label: {
                        SettingsRow(
                            icon: "square.and.pencil",
                            title: "Send Feedback",
                            showChevron: false
                        )
                    }
                    .buttonStyle(.plain)

                }

                // MARK: - Legal

                SettingsSection("Legal") {
                    Button {
                        UIApplication.shared.open(AppConfig.privacyPolicyURL)
                    } label: {
                        SettingsRow(icon: "hand.raised", title: "Privacy Policy", showChevron: false, trailingIcon: "arrow.up.right")
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        UIApplication.shared.open(AppConfig.termsOfUseURL)
                    } label: {
                        SettingsRow(icon: "doc.text", title: "Terms of Service", showChevron: false, trailingIcon: "arrow.up.right")
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    SettingsRow(
                        icon: "info.circle",
                        title: "Version",
                        value: appVersion,
                        showChevron: false
                    )
                }

                // MARK: - Debug (only in DEBUG builds)
                #if DEBUG
                SettingsSection("Developer") {
                    Button {
                        SettingsView.resetOnboardingState(
                            userId: authStore.userId,
                            forceOnboardingFlow: true
                        )
                        Task {
                            try? await authStore.signOut()
                        }
                    } label: {
                        SettingsRow(icon: "arrow.counterclockwise", title: "Reset Onboarding (Sign Out)", showChevron: false)
                    }

                    Button {
                        // Reset all onboarding + discovery flags without signing out.
                        SettingsView.resetOnboardingState(
                            userId: authStore.userId,
                            forceOnboardingFlow: true
                        )
                        UserDefaults.standard.removeObject(forKey: WidgetDiscoverySheet.dismissedKey)
                        WidgetDiscoveryLogic.reset()
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                    } label: {
                        SettingsRow(icon: "repeat", title: "Test Full Flow (Stay Signed In)", showChevron: false)
                    }

                    Button {
                        showTrialReminderTest = true
                    } label: {
                        SettingsRow(icon: "bell.badge", title: "Test Trial Reminder Sheet", showChevron: false)
                    }

                    Button {
                        showWidgetDiscoveryTest = true
                    } label: {
                        SettingsRow(icon: "square.grid.2x2", title: "Test Widget Discovery Sheet", showChevron: false)
                    }
                }
                #endif

                // MARK: - Delete Account

                VStack(spacing: 0) {
                    Button {
                        showSignOutConfirmation = true
                    } label: {
                        SettingsRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            title: "Sign Out",
                            showChevron: false
                        )
                    }
                    .buttonStyle(.plain)

                    if authStore.user?.deletionScheduledAt == nil {
                        SettingsDivider()

                        Button {
                            showDeleteConfirmation = true
                        } label: {
                            SettingsRow(
                                icon: "trash",
                                title: "Delete Account",
                                showChevron: false
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(cardColor)
                .clipShape(RoundedRectangle(cornerRadius: 24))
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(backgroundColor.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $importedNote) { note in
            NoteDetailView(note: note, initialContent: noteStore.displayContent(for: note))
        }
        .fileImporter(
            isPresented: $showAudioImporter,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: false
        ) { result in
            handleAudioImport(result)
        }
        .fullScreenCover(isPresented: $showGuestPaywall) {
            OnboardingPaywallStep(
                onPurchaseCompleted: { _, _ in showGuestPaywall = false },
                onRestored: { showGuestPaywall = false },
                onDismiss: { showGuestPaywall = false }
            )
        }
        .alert("Sign Out?", isPresented: $showSignOutConfirmation) {
            Button("Sign Out", role: .destructive) {
                Task { @MainActor in
                    try? await authStore.signOut()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
            Button("Schedule Deletion", role: .destructive) {
                Task {
                    isDeletionLoading = true
                    defer { isDeletionLoading = false }
                    do {
                        try await authStore.scheduleDeleteAccount()
                    } catch {
                        authStore.error = "Could not schedule deletion."
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account will be scheduled for deletion in 30 days. During this period you can sign back in and cancel. After 30 days, all your data will be permanently deleted.")
        }
        .alert("Cancel Deletion?", isPresented: $showCancelDeletion) {
            Button("Cancel Deletion") {
                Task {
                    isDeletionLoading = true
                    defer { isDeletionLoading = false }
                    do {
                        try await authStore.cancelDeleteAccount()
                    } catch {
                        authStore.error = "Could not cancel deletion."
                    }
                }
            }
            Button("Keep Deletion", role: .cancel) {}
        } message: {
            Text("Your account is scheduled for deletion. Would you like to cancel?")
        }
        .sheet(isPresented: $showTrialReminderTest) {
            TrialReminderSheet {
                showTrialReminderTest = false
            }
            .presentationDetents([.medium])
            .presentationBackground { SheetBackground() }
        }
        .sheet(isPresented: $showWidgetDiscoveryTest) {
            WidgetDiscoverySheet()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground { SheetBackground() }
        }
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func handleAudioImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let sourceURL = urls.first else { return }
        guard !isGuestAtLimit else {
            showGuestPaywall = true
            return
        }

        Task { @MainActor in
            do {
                let note = try await noteStore.importAudioNote(
                    from: sourceURL,
                    userId: authStore.userId,
                    categoryId: nil,
                    language: settingsStore.language == "auto" ? nil : settingsStore.language,
                    customDictionary: settingsStore.customDictionary
                )
                withAnimation(.snappy) {
                    importedNote = note
                }
            } catch {
                noteStore.lastError = error.localizedDescription
            }
        }
    }

    private func openSupportPage() {
        UIApplication.shared.open(AppConfig.supportURL)
    }


    private func openFeedbackEmail() {
        let subject = "Talkdraft Feedback (\(appVersion))".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:support@talkdraft.app?subject=\(subject)") {
            UIApplication.shared.open(url)
        }
    }

    private func languageDisplayName(_ code: String) -> String {
        if code == "auto" { return "Auto-detect" }
        let locale = Locale(identifier: "en")
        return locale.localizedString(forLanguageCode: code) ?? code
    }
}

// MARK: - Settings Section

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)

            VStack(spacing: 0) {
                content
            }
            .background(colorScheme == .dark ? Color.darkSurface : .white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
    }
}

// MARK: - Settings Row

private struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var showChevron: Bool = true
    var trailingIcon: String? = nil

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Color.brand)
                .frame(width: 24)

            Text(title)
                .font(.body)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            Spacer()

            if let value {
                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            } else if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .contentShape(Rectangle())
    }
}

// MARK: - Settings Divider

private struct SettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Divider()
            .padding(.leading, 52)
    }
}

// MARK: - Language Picker

private struct LanguagePickerView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private var languages: [(String, String)] {
        [("auto", "Auto-detect")] + SettingsStore.supportedLanguages.map { ($0.code, $0.name) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(languages.enumerated()), id: \.offset) { index, lang in
                    Button {
                        settingsStore.language = lang.0
                        dismiss()
                    } label: {
                        HStack {
                            Text(lang.1)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(
                                    settingsStore.language == lang.0 ? Color.brand : .primary
                                )
                            Spacer()
                            if settingsStore.language == lang.0 {
                                Image(systemName: "checkmark")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(Color.brand)
                            }
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.selection, trigger: settingsStore.language)

                    if index < languages.count - 1 {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .background(colorScheme == .dark ? Color.darkSurface : .white)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .padding(.horizontal, 20)
            .padding(.top, 8)
        }
        .background(
            (colorScheme == .dark ? Color.darkBackground : .warmBackground)
                .ignoresSafeArea()
        )
        .navigationTitle("Recording Language")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Theme Picker

private struct ThemeInlinePicker: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Picker("Appearance", selection: Bindable(settingsStore).theme) {
            ForEach(SettingsStore.AppTheme.allCases, id: \.self) { theme in
                Text(theme.displayName)
                    .tag(theme)
            }
        }
        .pickerStyle(.segmented)
        .sensoryFeedback(.selection, trigger: settingsStore.theme)
    }
}
