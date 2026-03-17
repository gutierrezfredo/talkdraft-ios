import SwiftUI
import UserNotifications

struct OnboardingNotificationsStep: View {
    let onComplete: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Luna mascot in brand circle
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(colorScheme == .dark ? 0.20 : 0.12))
                    .frame(width: 220, height: 220)

                LunaMascotView(.email, size: 180)
            }
            .padding(.bottom, 32)

            // Headline
            Text("Get a reminder before your trial ends")
                .font(.brandTitle)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            // Body
            Text("Enable notifications and we'll let you know before you're charged.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

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
            .padding(.bottom, 8)
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
        content.title = "Your Talkdraft trial ends in 2 days"
        content.body = "Cancel before then if you don't want your subscription to continue."
        content.sound = .default

        // Fire 5 days from now (2 days before 7-day trial ends)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: 5 * 24 * 60 * 60,
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
