import SwiftUI

struct SettingsView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptionStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteConfirmation = false
    @State private var showSignOutConfirmation = false
    @State private var showCancelDeletion = false
    @State private var isDeletionLoading = false
    @State private var showPaywall = false

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    private var cardColor: Color {
        colorScheme == .dark ? .darkSurface : .white
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
                        ThemePickerView()
                    } label: {
                        SettingsRow(
                            icon: "circle.lefthalf.filled",
                            title: "Appearance",
                            value: settingsStore.theme.displayName
                        )
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - Account

                SettingsSection("Account") {
                    Button {
                        if subscriptionStore.isPro {
                            if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        SettingsRow(
                            icon: "creditcard",
                            title: "Manage Subscription",
                            value: subscriptionStore.isPro ? "Pro" : "Free"
                        )
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - Legal

                SettingsSection("Legal") {
                    Button {
                        if let url = URL(string: "https://gutierrezfredo.github.io/spiritnotes-ios/privacy.html") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        SettingsRow(icon: "hand.raised", title: "Privacy Policy")
                    }
                    .buttonStyle(.plain)

                    SettingsDivider()

                    Button {
                        if let url = URL(string: "https://gutierrezfredo.github.io/spiritnotes-ios/terms.html") {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        SettingsRow(icon: "doc.text", title: "Terms of Service")
                    }
                    .buttonStyle(.plain)
                }

                // MARK: - About

                SettingsSection("About") {
                    SettingsRow(
                        icon: "info.circle",
                        title: "Version",
                        value: appVersion,
                        showChevron: false
                    )
                }

                // MARK: - Actions

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
                            HStack(spacing: 12) {
                                Image(systemName: "trash")
                                    .font(.body)
                                    .foregroundStyle(.red)
                                    .frame(width: 24)
                                Text("Delete Account")
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.red)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 56)
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .confirmationDialog(
            "Sign Out",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out") {
                Task { @MainActor in
                    try? await authStore.signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .confirmationDialog(
            "Delete Account",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
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
        } message: {
            Text("Your account will be scheduled for deletion in 30 days. During this period you can sign back in and cancel. After 30 days, all your data will be permanently deleted.")
        }
        .confirmationDialog(
            "Cancel Deletion",
            isPresented: $showCancelDeletion,
            titleVisibility: .visible
        ) {
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
    }

    // MARK: - Helpers

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private func languageDisplayName(_ code: String) -> String {
        switch code {
        case "auto": "Auto-detect"
        case "en": "English"
        case "es": "Spanish"
        case "fr": "French"
        case "de": "German"
        case "pt": "Portuguese"
        case "it": "Italian"
        case "ja": "Japanese"
        case "ko": "Korean"
        case "zh": "Chinese"
        default: code
        }
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

            if showChevron {
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

    private let languages: [(String, String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("es", "Spanish"),
        ("fr", "French"),
        ("de", "German"),
        ("pt", "Portuguese"),
        ("it", "Italian"),
        ("ja", "Japanese"),
        ("ko", "Korean"),
        ("zh", "Chinese"),
    ]

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

private struct ThemePickerView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(Array(SettingsStore.AppTheme.allCases.enumerated()), id: \.offset) { index, theme in
                    Button {
                        settingsStore.theme = theme
                        dismiss()
                    } label: {
                        HStack {
                            Text(theme.displayName)
                                .font(.body)
                                .fontWeight(.semibold)
                                .foregroundStyle(
                                    settingsStore.theme == theme ? Color.brand : .primary
                                )
                            Spacer()
                            if settingsStore.theme == theme {
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
                    .sensoryFeedback(.selection, trigger: settingsStore.theme)

                    if index < SettingsStore.AppTheme.allCases.count - 1 {
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
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

