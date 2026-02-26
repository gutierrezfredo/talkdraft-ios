import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var showEmailForm = false

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // Logo / Title
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.brand)

                    Text("Create account.\nOr log in if you have one")
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)

                    Text("Save all your notes securely and access\nthem from any device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Error
                if let error = authStore.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                // Sign-in buttons
                VStack(spacing: 12) {
                    // Google — primary
                    Button {
                        Task { await authStore.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image("google-logo")
                                .resizable()
                                .frame(width: 20, height: 20)
                            Text("Continue with Google")
                                .fontWeight(.semibold)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(Color.brand))
                    }
                    .buttonStyle(.plain)

                    // Email
                    Button {
                        showEmailForm = true
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "envelope.fill")
                                .font(.body)
                            Text("Continue with Email")
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

                    // Apple
                    SignInWithAppleButton(.continue) { request in
                        authStore.appleSignInRequest(request)
                    } onCompletion: { result in
                        Task { await authStore.handleAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 56)
                    .clipShape(Capsule())
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

                Spacer()

                // Terms
                Text("By signing in, you agree to our [Terms of Use](https://spiritnotes.app/terms) and [Privacy Policy](https://spiritnotes.app/privacy).")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 16)
            }
        }
        .sheet(isPresented: $showEmailForm) {
            EmailSignInSheet()
        }
    }
}

// MARK: - Email Sign-In Sheet

private struct EmailSignInSheet: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email, password
    }

    private var isValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 6
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .focused($focusedField, equals: .email)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.darkSurface : .white)
                            )

                        SecureField("Password", text: $password)
                            .textContentType(isSignUp ? .newPassword : .password)
                            .focused($focusedField, equals: .password)
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(colorScheme == .dark ? Color.darkSurface : .white)
                            )

                        if isSignUp {
                            Text("Password must be at least 6 characters")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let error = authStore.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        submit()
                    } label: {
                        Group {
                            if authStore.isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(isSignUp ? "Create Account" : "Sign In")
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(Capsule().fill(Color.brand))
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid || authStore.isLoading)
                    .opacity(isValid ? 1 : 0.4)

                    Button {
                        withAnimation(.snappy) {
                            isSignUp.toggle()
                            authStore.error = nil
                        }
                    } label: {
                        Text(isSignUp ? "Already have an account? **Sign In**" : "Don't have an account? **Sign Up**")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .background(
                (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                    .ignoresSafeArea()
            )
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Email")
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
            .onAppear {
                focusedField = .email
            }
            .onSubmit {
                switch focusedField {
                case .email:
                    focusedField = .password
                case .password:
                    if isValid { submit() }
                case nil:
                    break
                }
            }
        }
    }

    private func submit() {
        focusedField = nil
        Task {
            do {
                if isSignUp {
                    try await authStore.signUp(email: email, password: password)
                } else {
                    try await authStore.signIn(email: email, password: password)
                }
                dismiss()
            } catch {
                // Error is already set on authStore
            }
        }
    }
}
