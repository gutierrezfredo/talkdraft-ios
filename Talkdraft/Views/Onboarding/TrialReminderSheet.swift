import SwiftUI
import UserNotifications

enum TrialReminderPermissionState: Equatable {
    case needsPermission
    case enabled
    case blocked

    static func from(_ status: UNAuthorizationStatus) -> Self {
        switch status {
        case .authorized, .provisional, .ephemeral:
            .enabled
        case .notDetermined:
            .needsPermission
        case .denied:
            .blocked
        @unknown default:
            .needsPermission
        }
    }
}

struct TrialReminderSheet: View {
    let onComplete: () -> Void

    var body: some View {
        TrialReminderContent(onComplete: onComplete)
    }
}

struct OnboardingTrialReminderStep: View {
    let onComplete: () -> Void

    var body: some View {
        VStack {
            Spacer(minLength: 24)
            TrialReminderContent(onComplete: onComplete)
                .padding(.horizontal, 24)
            Spacer()
        }
    }
}

private struct TrialReminderContent: View {
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var permissionState: TrialReminderPermissionState = .needsPermission
    @State private var hasScheduledReminder = false

    var body: some View {
        VStack(spacing: 24) {
            statusIcon

            VStack(spacing: 8) {
                Text(permissionTitle)
                    .font(.brandTitle)
                    .fontDesign(nil)

                Text(permissionMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)

            VStack(spacing: 8) {
                primaryButton

                if permissionState == .needsPermission {
                    Button {
                        onComplete()
                    } label: {
                        Text("Not Now")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else if permissionState == .blocked {
                    Button {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            openURL(settingsURL)
                        }
                    } label: {
                        Text("Open Settings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .task {
            await refreshPermissionState()
        }
    }

    private var permissionTitle: String {
        switch permissionState {
        case .enabled:
            "Trial Reminder Ready"
        case .blocked:
            "Notifications Off"
        case .needsPermission:
            "Trial Reminder Active"
        }
    }

    private var permissionMessage: String {
        switch permissionState {
        case .enabled:
            "Notifications are already enabled. Your Day 6 reminder is ready, so you can head straight into Talkdraft."
        case .blocked:
            "Notifications are currently turned off for Talkdraft. You can continue now and enable them later in Settings."
        case .needsPermission:
            "To keep our promise, we'll remind you 24h before your trial ends. Enable notifications to stay in control."
        }
    }

    private var statusIcon: some View {
        ZStack {
            Circle()
                .fill(iconBackgroundColor)
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .stroke(Color.brand.opacity(0.10), lineWidth: 1.5)
                )
                .shadow(color: Color.brand.opacity(0.08), radius: 8, x: 0, y: 2)

            if permissionState == .enabled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Color.green)
                    .symbolRenderingMode(.hierarchical)
            } else {
                Text("🔔")
                    .font(.largeTitle)
            }
        }
    }

    private var iconBackgroundColor: Color {
        switch permissionState {
        case .enabled:
            return Color.green.opacity(colorScheme == .dark ? 0.22 : 0.12)
        case .blocked:
            return Color.secondary.opacity(colorScheme == .dark ? 0.20 : 0.10)
        case .needsPermission:
            return Color.orange.opacity(colorScheme == .dark ? 0.25 : 0.12)
        }
    }

    private var primaryButton: some View {
        Button {
            Task {
                switch permissionState {
                case .enabled:
                    await completeOnboarding()
                case .blocked:
                    await completeOnboarding()
                case .needsPermission:
                    await requestAndSchedule()
                    await completeOnboarding()
                }
            }
        } label: {
            Text(primaryButtonTitle)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Color.brand, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var primaryButtonTitle: String {
        switch permissionState {
        case .enabled, .blocked:
            "Continue"
        case .needsPermission:
            "Enable Notifications"
        }
    }

    private func refreshPermissionState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let state = TrialReminderPermissionState.from(settings.authorizationStatus)

        await MainActor.run {
            permissionState = state
        }

        if state == .enabled {
            await MainActor.run {
                scheduleTrialReminderIfNeeded()
            }
        }
    }

    private func requestAndSchedule() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false

        if granted {
            await MainActor.run {
                permissionState = .enabled
                scheduleTrialReminderIfNeeded()
            }
        } else {
            await refreshPermissionState()
        }
    }

    @MainActor
    private func scheduleTrialReminderIfNeeded() {
        guard !hasScheduledReminder else { return }
        hasScheduledReminder = true

        let content = UNMutableNotificationContent()
        content.title = "Talkdraft Trial Reminder"
        content.body = "Your 7-day trial ends tomorrow. Keep capturing, or manage your subscription in Settings."
        content.sound = .default

        // Fire 6 days (144 hours) from now
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 6 * 24 * 60 * 60,
            repeats: false
        )

        let request = UNNotificationRequest(
            identifier: "trial-reminder",
            content: content,
            trigger: trigger
        )

        UNUserNotificationCenter.current().add(request)
    }

    @MainActor
    private func completeOnboarding() {
        onComplete()
    }
}
