import AuthenticationServices
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
                        authStore.error = nil
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
                    Text("Skip login")
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
    @FocusState private var emailFocused: Bool

    private var isValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return trimmed.contains("@") && trimmed.contains(".")
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? .darkBackground : .warmBackground
    }

    private var effectiveCooldown: Int {
        max(resendCooldown, authStore.magicLinkCooldownRemaining)
    }

    private var isEmailSubmitDisabled: Bool {
        !isValid || authStore.isSendingMagicLink || authStore.magicLinkCooldownRemaining > 0
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
                        authStore.error = nil
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
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
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
                        .tint(Color.brand)
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

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture {
                    emailFocused = true
                }
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            emailSubmitBar
        }
    }

    private var emailSubmitBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .clear,
                    backgroundColor.opacity(0.85),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)

            Button {
                sendLink()
            } label: {
                Group {
                    if authStore.isSendingMagicLink {
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
            .disabled(isEmailSubmitDisabled)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .background(backgroundColor.opacity(0.85))
        }
    }

    private var sentConfirmation: some View {
        VStack(spacing: 0) {
            // Luna mascot
            ZStack {
                Circle()
                    .fill(Color.brand.opacity(colorScheme == .dark ? 1.0 : 0.20))
                    .frame(width: 220, height: 220)

                LunaMascotView(.email, size: 180)
            }
            .padding(.top, 40)
            .padding(.bottom, 24)

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

            if let error = authStore.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }

            // Resend
            Button {
                resendLink()
            } label: {
                Text(effectiveCooldown > 0 ? "Resend in \(effectiveCooldown)s" : "Resend email")
                    .font(.subheadline)
                    .foregroundStyle(effectiveCooldown > 0 ? .tertiary : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(effectiveCooldown > 0)
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
        .onChange(of: email) { _, _ in
            if authStore.magicLinkCooldownRemaining == 0 {
                authStore.error = nil
            }
        }
    }

    private func sendLink() {
        emailFocused = false
        Task {
            do {
                try await authStore.sendMagicLink(email: email)
                withAnimation(.snappy) { magicLinkSent = true }
                startCooldown()
            } catch {
                // Error is surfaced through authStore.error on the form.
            }
        }
    }

    private func resendLink() {
        Task {
            do {
                try await authStore.sendMagicLink(email: email)
                startCooldown()
            } catch {
                // Error is surfaced through authStore.error on the confirmation screen.
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
