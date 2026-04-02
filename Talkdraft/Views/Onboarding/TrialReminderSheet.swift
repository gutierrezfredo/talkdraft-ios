import SwiftUI
import UserNotifications

struct TrialReminderSheet: View {
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            // Bell icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.25 : 0.12))
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(Color.brand.opacity(0.10), lineWidth: 1.5)
                    )
                    .shadow(color: Color.brand.opacity(0.08), radius: 8, x: 0, y: 2)
                Text("🔔")
                    .font(.largeTitle)
            }

            // Text
            VStack(spacing: 8) {
                Text("Trial Reminder Active")
                    .font(.brandTitle)
                    .fontDesign(nil)

                Text("To keep our promise, we'll remind you 24h before your trial ends. Enable notifications to stay in control.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)

            // CTAs
            VStack(spacing: 8) {
                Button {
                    Task {
                        await requestAndSchedule()
                        onComplete()
                    }
                } label: {
                    Text("Enable Notifications")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Color.brand, in: Capsule())
                }
                .buttonStyle(.plain)

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
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private func requestAndSchedule() async {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false

        if granted {
            scheduleTrialReminder()
        }
    }

    private func scheduleTrialReminder() {
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
}
