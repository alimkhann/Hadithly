import SwiftUI
import AuthenticationServices
import ClerkKit

extension Error {
    var isCancellation: Bool {
        self is CancellationError
            || (self as? URLError)?.code == .cancelled
            || (self as? ASAuthorizationError)?.code == .canceled
    }
}

/// Custom sign-in flows (no Clerk hosted UI): Apple via native Sign in with
/// Apple, Google via the system browser, and email via a one-time code.
/// Every method ends in the same place: onAuthenticated runs the post-sign-in
/// sync (Convex user record + guest merge) and dismisses the sheet.
struct SignInView: View {
    /// Runs the post-sign-in sync and dismisses. Called directly on flow
    /// completion — ClerkKit's independent auth events do not fire for
    /// custom service-level flows.
    var onAuthenticated: () async -> Void

    var onDismiss: () -> Void = {}

    private enum Mode {
        case methods
        case emailEntry
        case codeEntry(isSignUp: Bool)
    }

    @State private var mode: Mode = .methods
    @State private var email = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .methods:
                    methodsScreen
                case .emailEntry:
                    emailEntryScreen
                case .codeEntry(let isSignUp):
                    codeEntryScreen(isSignUp: isSignUp)
                }
            }
            .navigationTitle("Sign in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { onDismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Method selection

    private var methodsScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Sync your reading")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Guests can read everything. An account just carries your bookmarks and notes across devices.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            .padding(.top, 24)

            Spacer()

            VStack(spacing: 12) {
                providerButton(
                    title: "Continue with Apple",
                    icon: "apple.logo",
                    background: .white,
                    foreground: .black
                ) {
                    try await Clerk.shared.auth.signInWithApple()
                }
                .accessibilityIdentifier("signin.apple")

                providerButton(
                    title: "Continue with Google",
                    icon: nil,
                    background: Theme.surfaceElevated,
                    foreground: Theme.textPrimary
                ) {
                    try await Clerk.shared.auth.signInWithOAuth(provider: .google)
                }
                .accessibilityIdentifier("signin.google")

                HStack(spacing: 12) {
                    Rectangle().fill(Theme.surfaceElevated).frame(height: 1)
                    Text("or")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Rectangle().fill(Theme.surfaceElevated).frame(height: 1)
                }
                .padding(.vertical, 4)

                Button {
                    errorMessage = nil
                    mode = .emailEntry
                } label: {
                    Text("Continue with email")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
                .accessibilityIdentifier("signin.email")
            }
            .padding(.horizontal, 20)

            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()

            Button("Keep reading as a guest") {
                onDismiss()
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Email entry

    private var emailEntryScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("What's your email?")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("We'll send a six-digit sign-in code.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 24)

            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .accessibilityIdentifier("signin.email.field")

            Button {
                Task { await startEmailFlow() }
            } label: {
                if isBusy {
                    ProgressView().tint(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    Text("Send code")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .buttonStyle(.plain)
            .background(Theme.accent)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .disabled(isBusy || email.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("signin.email.send")

            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Code entry

    private func codeEntryScreen(isSignUp: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Check your email")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Enter the code we sent to \(email).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            TextField("000000", text: $code)
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter(\.isNumber).prefix(6))
                }
                .onSubmit { Task { await submitCode(isSignUp: isSignUp) } }
                .accessibilityIdentifier("signin.code.field")

            Button {
                Task { await submitCode(isSignUp: isSignUp) }
            } label: {
                if isBusy {
                    ProgressView().tint(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    Text("Verify")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
            .buttonStyle(.plain)
            .background(Theme.accent)
            .foregroundStyle(.black)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .disabled(isBusy || code.count < 6)
            .accessibilityIdentifier("signin.code.verify")

            Button("Resend code") {
                Task { await resendCode(isSignUp: isSignUp) }
            }
            .font(.subheadline)
            .foregroundStyle(Theme.accent)
            .padding(.top, 12)
            .disabled(isBusy)

            if let errorMessage {
                ErrorBanner(message: errorMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    // MARK: - Actions

    private func providerButton(
        title: String,
        icon: String?,
        background: Color,
        foreground: Color,
        action: @escaping () async throws -> TransferFlowResult
    ) -> some View {
        Button {
            Task {
                isBusy = true
                errorMessage = nil
                defer { isBusy = false }
                do {
                    let result = try await action()
                    switch result {
                    case .signIn(let signIn):
                        if signIn.status == .complete {
                            await onAuthenticated()
                        } else {
                            errorMessage = "Sign-in needs another step. This flow is not fully supported yet."
                        }
                    case .signUp(let signUp):
                        if signUp.status == .complete {
                            await onAuthenticated()
                        } else {
                            errorMessage = "Sign-in needs another step. This flow is not fully supported yet."
                        }
                    }
                } catch {
                    if !error.isCancellation {
                        present(error)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                }
                Text(title)
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    private func startEmailFlow() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            _ = try await Clerk.shared.auth.signInWithEmailCode(
                emailAddress: normalizedEmail
            )
            mode = .codeEntry(isSignUp: false)
        } catch let error as ClerkAPIError
        where ["form_identifier_not_found", "invitation_account_not_exists"].contains(error.code) {
            // No account yet — continue as sign-up with the same address.
            do {
                let signUp = try await Clerk.shared.auth.signUp(emailAddress: normalizedEmail)
                _ = try await signUp.sendEmailCode()
                mode = .codeEntry(isSignUp: true)
            } catch {
                present(error)
            }
        } catch {
            present(error)
        }
    }

    private func submitCode(isSignUp: Bool) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            if isSignUp {
                guard let signUp = Clerk.shared.auth.currentSignUp else {
                    errorMessage = "The sign-up session expired. Please start again."
                    return
                }
                var updated = try await signUp.verifyEmailCode(code)
                if updated.status == .missingRequirements {
                    // Hadithly never asks for passwords or usernames in its
                    // UI. If the Clerk instance still requires them at
                    // sign-up, fill generated values so email-code sign-up
                    // completes without user-facing fields.
                    updated = try await fulfillMissingRequirements(updated)
                }
                if updated.status == .complete {
                    await onAuthenticated()
                } else if updated.status != .missingRequirements {
                    errorMessage = "Sign-up could not be completed. Please try again."
                }
            } else {
                guard let signIn = Clerk.shared.auth.currentSignIn else {
                    errorMessage = "The sign-in session expired. Please start again."
                    return
                }
                let updated = try await signIn.verifyCode(code)
                if updated.status == .complete {
                    await onAuthenticated()
                }
            }
        } catch let error as ClerkAPIError where error.code == "verification_already_verified" {
            await handleAlreadyVerified(isSignUp: isSignUp)
        } catch {
            present(error)
        }
    }

    /// A retry after the verification already succeeded (e.g. the completion
    /// step was interrupted). If the flow is complete, finish it.
    private func handleAlreadyVerified(isSignUp: Bool) async {
        if isSignUp, let signUp = Clerk.shared.auth.currentSignUp, signUp.status == .complete {
            await onAuthenticated()
        } else if let signIn = Clerk.shared.auth.currentSignIn, signIn.status == .complete {
            await onAuthenticated()
        } else {
            errorMessage = "This code was already used. Please request a new one."
        }
    }

    private func fulfillMissingRequirements(_ signUp: SignUp) async throws -> SignUp {
        var suffix = String(UUID().uuidString.prefix(8)).lowercased()
        suffix = suffix.replacingOccurrences(of: "-", with: "0")
        let username = "reader_\(suffix)"
        let password = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24)) + "9xK"
        return try await signUp.update(password: password, username: username)
    }

    private func resendCode(isSignUp: Bool) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            if isSignUp {
                if let signUp = Clerk.shared.auth.currentSignUp {
                    _ = try await signUp.sendEmailCode()
                }
            } else if let signIn = Clerk.shared.auth.currentSignIn {
                _ = try await signIn.sendEmailCode()
            }
        } catch {
            present(error)
        }
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func present(_ error: Error) {
        if let apiError = error as? ClerkAPIError {
            errorMessage = apiError.longMessage ?? apiError.errorDescription
        } else {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(Theme.destructive)
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Theme.destructive.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    SignInView(
        onAuthenticated: {},
        onDismiss: {}
    )
}
