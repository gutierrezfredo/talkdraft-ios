import SwiftUI

struct LoginView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var email = ""
    @State private var password = ""
    @State private var isSignUp = false
    @State private var showError = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case email, password
    }

    private var isValid: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
            && password.count >= 6
    }

    var body: some View {
        ZStack {
            (colorScheme == .dark ? Color.darkBackground : Color.warmBackground)
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    Spacer(minLength: 60)

                    // Logo / Title
                    VStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.brand)

                        Text("SpiritNotes")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Say it messy. Read it clean")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 16)

                    // Fields
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
                    .padding(.horizontal, 24)

                    // Error
                    if let error = authStore.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Submit button
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
                        .background(
                            Capsule().fill(Color.brand)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isValid || authStore.isLoading)
                    .opacity(isValid ? 1 : 0.4)
                    .padding(.horizontal, 24)

                    // Toggle sign in / sign up
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

                    Spacer(minLength: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
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

    private func submit() {
        focusedField = nil
        Task {
            do {
                if isSignUp {
                    try await authStore.signUp(email: email, password: password)
                } else {
                    try await authStore.signIn(email: email, password: password)
                }
            } catch {
                // Error is already set on authStore
            }
        }
    }
}
