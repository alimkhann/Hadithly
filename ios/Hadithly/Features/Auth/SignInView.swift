import SwiftUI
import AuthenticationServices
import ClerkKit

extension Error {
    var isCancellation: Bool {
        self is CancellationError
            || (self as? URLError)?.code == .cancelled
            || (self as? ASAuthorizationError)?.code == .canceled
            || (self as? ASWebAuthenticationSessionError)?.code == .canceledLogin
    }
}

/// Custom sign-in flows (no Clerk hosted UI): Apple via native Sign in with
/// Apple, Google via the system browser, and email + password for standard
/// accounts. Sign-up asks for an email and password only; a username is
/// generated from the email address and can be changed later in Settings.
/// Email verification codes confirm the address. Every method ends in the
/// same place: onAuthenticated runs the post-sign-in sync (Convex user
/// record + guest merge) and dismisses the sheet.
struct SignInView: View {
    /// Runs the post-sign-in sync and dismisses. Called directly on flow
    /// completion — ClerkKit's independent auth events do not fire for
    /// custom service-level flows.
    var onAuthenticated: () async -> Void

    var onDismiss: () -> Void = {}

    @Environment(AppEnvironment.self) private var environment

    private enum Mode {
        case methods
        case passwordSignIn
        case signUp
        case emailEntry
        case codeEntry(isSignUp: Bool)
        case forgotPasswordEntry
        case resetPassword
    }

    @State private var mode: Mode = .methods
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var newPassword = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .methods:
                    methodsScreen
                case .passwordSignIn:
                    passwordSignInScreen
                case .signUp:
                    signUpScreen
                case .emailEntry:
                    emailEntryScreen
                case .codeEntry(let isSignUp):
                    codeEntryScreen(isSignUp: isSignUp)
                case .forgotPasswordEntry:
                    forgotPasswordEntryScreen
                case .resetPassword:
                    resetPasswordScreen
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

                hostedAuthButton(
                    title: "Continue with Google",
                    background: Theme.surfaceElevated,
                    foreground: Theme.textPrimary
                )
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
                    resetFields()
                    errorMessage = nil
                    mode = .passwordSignIn
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

                Button("Create account") {
                    resetFields()
                    errorMessage = nil
                    mode = .signUp
                }
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .disabled(isBusy)
                .accessibilityIdentifier("signin.createAccount")

                LegalText(
                    termsURL: environment.config.termsOfUseURL,
                    privacyURL: environment.config.privacyPolicyURL
                )
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

    // MARK: - Password sign-in

    private var passwordSignInScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Welcome back")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Sign in with your email or username.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 24)

            TextField("Email or username", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .accessibilityIdentifier("signin.identifier.field")

            SecureField("Password", text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .accessibilityIdentifier("signin.password.field")

            Button {
                Task { await submitPasswordSignIn() }
            } label: {
                if isBusy {
                    ProgressView().tint(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    Text("Sign in")
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
            .disabled(isBusy || normalizedIdentifier.isEmpty || password.isEmpty)
            .accessibilityIdentifier("signin.password.submit")

            Button("Forgot password?") {
                errorMessage = nil
                mode = .forgotPasswordEntry
            }
            .font(.subheadline)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 12)
            .disabled(isBusy)

            Button("Sign in with a code instead") {
                errorMessage = nil
                mode = .emailEntry
            }
            .font(.footnote)
            .foregroundStyle(Theme.accent)
            .padding(.top, 8)
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

    // MARK: - Sign-up

    private var signUpScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Create your account")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Carry your bookmarks and notes across devices.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    TextField("you@example.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body)
                        .padding(16)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("signup.email.field")

                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body)
                        .padding(16)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("signup.password.field")

                    SecureField("Repeat password", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body)
                        .padding(16)
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("signup.confirmPassword.field")

                    if !confirmPassword.isEmpty && confirmPassword != password {
                        Text("Passwords do not match.")
                            .font(.footnote)
                            .foregroundStyle(Theme.destructive)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task { await submitSignUp() }
                    } label: {
                        if isBusy {
                            ProgressView().tint(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        } else {
                            Text("Create account")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                    .buttonStyle(.plain)
                    .background(Theme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(isBusy || !signUpInputIsValid)
                    .accessibilityIdentifier("signup.submit")

                    LegalText(
                        termsURL: environment.config.termsOfUseURL,
                        privacyURL: environment.config.privacyPolicyURL
                    )

                    if let errorMessage {
                        ErrorBanner(message: errorMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private var signUpInputIsValid: Bool {
        !normalizedEmail.isEmpty
            && password.count >= 8
            && confirmPassword == password
    }

    // MARK: - Email entry (code sign-in fallback)

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
            .disabled(isBusy || normalizedEmail.isEmpty)
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

    // MARK: - Forgot password

    private var forgotPasswordEntryScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Reset your password")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("We'll send a code to your email address.")
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

            Button {
                Task { await startPasswordReset() }
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
            .disabled(isBusy || normalizedEmail.isEmpty)

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

    private var resetPasswordScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Choose a new password")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text("Enter the code sent to \(email) and your new password.")
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

            SecureField("New password", text: $newPassword)
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 12)

            Button {
                Task { await submitPasswordReset() }
            } label: {
                if isBusy {
                    ProgressView().tint(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                } else {
                    Text("Set new password")
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
            .disabled(isBusy || code.count < 6 || newPassword.count < 8)

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

    /// Opens Clerk hosted authentication (Account Portal), which completes
    /// the whole provider round-trip and activates the session. The custom
    /// OAuth handshake loses the rotating-token nonce on callback, so social
    /// sign-in that needs the browser goes through hosted auth.
    private func hostedAuthButton(
        title: String,
        background: Color,
        foreground: Color
    ) -> some View {
        Button {
            Task {
                isBusy = true
                errorMessage = nil
                defer { isBusy = false }
                do {
                    _ = try await Clerk.shared.auth.startHostedAuth()
                    await onAuthenticated()
                } catch {
                    if !error.isCancellation {
                        present(error)
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                if isBusy {
                    ProgressView()
                        .tint(foreground)
                } else {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(foreground)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

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

    private func submitPasswordSignIn() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let signIn = try await Clerk.shared.auth.signInWithPassword(
                identifier: normalizedIdentifier,
                password: password
            )
            if signIn.status == .complete {
                await onAuthenticated()
            } else {
                errorMessage = "Sign-in needs another step. Please try again."
            }
        } catch let error as ClerkAPIError
        where ["form_identifier_not_found", "invitation_account_not_exists"].contains(error.code) {
            errorMessage = "No account found for that identifier. Create an account first."
        } catch {
            if !error.isCancellation {
                present(error)
            }
        }
    }

    private func submitSignUp() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let generatedUsername = Self.generatedUsername(from: normalizedEmail)
        do {
            let signUp = try await Clerk.shared.auth.signUp(
                emailAddress: normalizedEmail,
                password: password,
                username: generatedUsername
            )
            _ = try await signUp.sendEmailCode()
            mode = .codeEntry(isSignUp: true)
        } catch let error as ClerkAPIError
        where ["form_username_in_use", "form_param_format_invalid"].contains(error.code) && !generatedUsername.hasSuffix("0") {
            // The derived username was taken or malformed — retry once with
            // a numeric suffix before surfacing the error.
            isBusy = true
            defer { isBusy = false }
            do {
                let suffix = String(format: "%03d", Int.random(in: 100...999))
                let signUp = try await Clerk.shared.auth.signUp(
                    emailAddress: normalizedEmail,
                    password: password,
                    username: String(generatedUsername.prefix(24)) + suffix
                )
                _ = try await signUp.sendEmailCode()
                mode = .codeEntry(isSignUp: true)
            } catch {
                present(error)
            }
        } catch {
            present(error)
        }
    }

    /// The user never types a username: it is derived from the email local
    /// part (letters and digits only, at least 3 characters) so OAuth-created
    /// and password-created accounts stay consistent. Changeable in Settings.
    private static func generatedUsername(from email: String) -> String {
        let base = String(email.split(separator: "@").first ?? "")
            .filter { $0.isLetter || $0.isNumber }
            .lowercased()
        let trimmed = String(base.prefix(24))
        if trimmed.count >= 3 {
            return trimmed
        }
        return "reader\(Int.random(in: 100...999))"
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
            errorMessage = "No account found for that email. Create an account first."
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
                let updated = try await signUp.verifyEmailCode(code)
                if updated.status == .complete {
                    await onAuthenticated()
                } else {
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

    private func startPasswordReset() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let signIn = try await Clerk.shared.auth.signIn(normalizedEmail)
            _ = try await signIn.sendResetPasswordEmailCode()
            mode = .resetPassword
        } catch {
            present(error)
        }
    }

    private func submitPasswordReset() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            guard let signIn = Clerk.shared.auth.currentSignIn else {
                errorMessage = "The reset session expired. Please start again."
                return
            }
            let updated = try await signIn.verifyCode(code)
            let reset = try await updated.resetPassword(newPassword: newPassword)
            if reset.status == .complete {
                await onAuthenticated()
            } else {
                errorMessage = "Could not reset the password. Please try again."
            }
        } catch {
            present(error)
        }
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

    private func resetFields() {
        email = ""
        password = ""
        confirmPassword = ""
        newPassword = ""
        code = ""
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedIdentifier: String {
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

/// "By continuing, you agree to our Terms of Use and Privacy Policy." shown on
/// the method chooser and the email sign-up screen. Terms of Use and Privacy
/// Policy are tappable links that open the public policy pages.
private struct LegalText: View {
    let termsURL: URL?
    let privacyURL: URL?

    var body: some View {
        if let terms = termsURL, let privacy = privacyURL {
            legalLine(terms: terms, privacy: privacy)
        }
    }

    private func legalLine(terms: URL, privacy: URL) -> some View {
        var text = AttributedString("By continuing, you agree to our ")
        text.foregroundColor = Theme.textSecondary
        var termsPart = AttributedString("Terms of Use")
        termsPart.link = terms
        termsPart.foregroundColor = Theme.accent
        var andPart = AttributedString(" and ")
        andPart.foregroundColor = Theme.textSecondary
        var privacyPart = AttributedString("Privacy Policy")
        privacyPart.link = privacy
        privacyPart.foregroundColor = Theme.accent
        var dotPart = AttributedString(".")
        dotPart.foregroundColor = Theme.textSecondary
        return Text(text + termsPart + andPart + privacyPart + dotPart)
            .font(.caption)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

#Preview {
    SignInView(
        onAuthenticated: {},
        onDismiss: {}
    )
}
