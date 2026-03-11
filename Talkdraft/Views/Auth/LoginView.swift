import AuthenticationServices
import AVKit
import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showEmailForm = false

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    var body: some View {
        ZStack {
            backgroundColor.ignoresSafeArea()

            VStack(spacing: 0) {
                // Demo area
                demoPreview
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)

                // Tagline
                Text("Voice notes turned into\nclean, organized text.")
                    .font(.brandTitle2)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 28)

                // Error
                if let error = authStore.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 8)
                }

                // Sign-in buttons
                VStack(spacing: 12) {
                    // Apple
                    SignInWithAppleButton(.continue) { request in
                        authStore.appleSignInRequest(request)
                    } onCompletion: { result in
                        Task { await authStore.handleAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 56)
                    .clipShape(Capsule())

                    // Email
                    Button {
                        showEmailForm = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                                .font(.body)
                            Text("Continue with Email")
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.darkSurface : .white)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)

                // Continue without login
                Button {
                    Task { await authStore.signInAnonymously() }
                } label: {
                    Text("Continue without login")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 24)

                Spacer(minLength: 32)

                // Terms
                Text("By signing in, you agree to our [Terms of Use](https://gutierrezfredo.github.io/talkdraft-ios/legal/terms.html) and [Privacy Policy](https://gutierrezfredo.github.io/talkdraft-ios/legal/privacy.html).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .tint(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showEmailForm) {
            EmailSignInSheet()
        }
    }

    // MARK: - Demo Preview

    private var demoPreview: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "waveform")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.brand)
            }
        }
        .padding(.top, 32)
    }
}

// MARK: - Email Sign-In Sheet

private struct EmailSignInSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var magicLinkSent = false
    @State private var resendCooldown = 0
    @State private var videoPlayer: AVQueuePlayer?
    @State private var playerLooper: AVPlayerLooper?
    @FocusState private var emailFocused: Bool

    private var isValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    var body: some View {
        NavigationStack {
            Group {
                if magicLinkSent {
                    sentConfirmation
                } else {
                    emailForm
                }
            }
            .background(backgroundColor.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        if magicLinkSent {
                            withAnimation(.snappy) {
                                magicLinkSent = false
                                authStore.error = nil
                            }
                        } else {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }

    private var emailForm: some View {
        VStack(spacing: 0) {
            Text("Continue with your email")
                .font(.brandTitle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            Text("We'll send you a sign-in link. No password needed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)

            TextField("Enter your email", text: $email)
                .font(.brandTitle2)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($emailFocused)
                .padding(.horizontal, 24)
                .padding(.top, 120)
                .onAppear { emailFocused = true }
                .onSubmit { if isValid { sendLink() } }

            if let error = authStore.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            Spacer()

            Button {
                sendLink()
            } label: {
                Group {
                    if authStore.isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Continue")
                            .fontWeight(.semibold)
                    }
                }
                .foregroundStyle(isValid ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    Capsule().fill(isValid ? Color.brand : (colorScheme == .dark ? Color.darkSurface : Color.secondary.opacity(0.12)))
                )
            }
            .buttonStyle(.plain)
            .disabled(!isValid || authStore.isLoading)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private var sentConfirmation: some View {
        VStack(spacing: 0) {
            Spacer()

            // Video
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(0.12))
                    .frame(width: 220, height: 220)

                if let player = videoPlayer {
                    LoopingVideoView(player: player)
                        .frame(width: 180, height: 180)
                } else {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.brand)
                }
            }
            .padding(.bottom, 24)
            .onAppear { setupVideoPlayer() }
            .onDisappear { videoPlayer?.pause() }

            // Title
            Text("Check your email")
                .font(.brandTitle2)
                .padding(.bottom, 20)

            // Description
            Text("We sent a sign-in link to **\(email)**. Tap the link inside that email to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Resend
            Button {
                resendLink()
            } label: {
                Text(resendCooldown > 0 ? "Resend in \(resendCooldown)s" : "Resend email")
                    .font(.subheadline)
                    .foregroundStyle(resendCooldown > 0 ? .tertiary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(resendCooldown > 0)
            .padding(.top, 20)

            Spacer()

            // Bottom buttons
            VStack(spacing: 12) {
                Button {
                    if let url = URL(string: "message://") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Open Mail App")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(Color.brand))
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.snappy) {
                        magicLinkSent = false
                        authStore.error = nil
                    }
                } label: {
                    Text("Back")
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            Capsule()
                                .fill(colorScheme == .dark ? Color.darkSurface : Color.secondary.opacity(0.1))
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    private func setupVideoPlayer() {
        guard videoPlayer == nil,
              let url = Bundle.main.url(forResource: "mail-received", withExtension: "mp4")
        else { return }
        let item = AVPlayerItem(url: url)
        let player = AVQueuePlayer(playerItem: item)
        playerLooper = AVPlayerLooper(player: player, templateItem: item)
        player.isMuted = true
        player.play()
        videoPlayer = player
    }

    private func sendLink() {
        emailFocused = false
        withAnimation(.snappy) { magicLinkSent = true }
        Task {
            do {
                try await authStore.sendMagicLink(email: email)
                startCooldown()
            } catch {
                // Non-fatal — user already sees the confirmation screen
            }
        }
    }

    private func resendLink() {
        Task {
            do {
                try await authStore.sendMagicLink(email: email)
                startCooldown()
            } catch {
                // Non-fatal
            }
        }
    }

    private func startCooldown() {
        resendCooldown = 30
        Task {
            while resendCooldown > 0 {
                try? await Task.sleep(for: .seconds(1))
                resendCooldown -= 1
            }
        }
    }
}

