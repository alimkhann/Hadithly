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

enum AuthFailureMessage: String, CaseIterable {
    case action = "This action could not be completed. Please try again."
    case password = "The password is incorrect. Try again or reset it."
    case code = "That code is incorrect. Try again."
    case expired = "This code has expired. Request a new one."
    case longer = "Use a longer password."
    case stronger = "Choose a stronger password."
    case breached = "Choose a different password. This one appears in a data breach."
    case existing = "An account already uses that email or username. Try signing in."
    case rate = "Too many attempts. Wait a moment and try again."
    case connection = "Check your connection and try again."
    case session = "This session expired. Please start again."
    case step = "Another sign-in step is required. Use another sign-in method."
    case missing = "No account found for that identifier. Create an account first."
    case used = "This code was already used. Please request a new one."
    case mismatch = "Passwords do not match."

    static func select(code: String?, status: Int? = nil, network: Bool = false) -> Self {
        if status == 429 { return .rate }
        switch code {
        case "form_password_incorrect": return .password
        case "form_code_incorrect", "totp_incorrect_code": return .code
        case "verification_expired": return .expired
        case "form_password_length_too_short": return .longer
        case "form_password_not_strong_enough": return .stronger
        case "form_password_pwned": return .breached
        case "form_identifier_exists": return .existing
        case "form_identifier_not_found": return .missing
        case "too_many_requests", "verification_code_too_many_requests", "verification_code_too_many_attempts": return .rate
        default: return network ? .connection : .action
        }
    }

    static func from(_ error: Error) -> Self {
        select(code: (error as? ClerkAPIError)?.code,
               network: error is URLError || (error as NSError).domain == NSURLErrorDomain)
    }

    static func local(_ source: String) -> Self {
        if let message = Self(rawValue: source) { return message }
        switch source {
        case "The sign-up session expired. Please start again.", "The sign-in session expired. Please start again.", "The reset session expired. Please start again.": return .session
        case "Sign-in needs another step. This flow is not fully supported yet.", "Sign-in needs another step. Please try again.": return .step
        case "No account found for that email. Create an account first.": return .missing
        default: return .action
        }
    }
}

/// Custom sign-in flows (no Clerk hosted UI): Apple via native Sign in with
/// Apple, Google via the system browser, and email + password for standard
/// accounts. Sign-up asks for an email and password only; a username is
/// generated from the email address and can be changed later in Settings.
/// Email verification codes confirm the address. Every method ends in the
/// same place: onAuthenticated runs the post-sign-in sync (Convex user
/// record + guest merge) and returns to the caller's reading flow.
struct SignInView: View {
    /// Runs the post-sign-in sync and dismisses. Called directly on flow
    /// completion — ClerkKit's independent auth events do not fire for
    /// custom service-level flows.
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @Environment(\.colorScheme) private var colorScheme
    var onAuthenticated: () async -> Void

    var onDismiss: () -> Void = {}
    var onCreationResult: ((Bool?) -> Void)? = nil
    var onAuthenticationFailure: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    private enum Mode: Hashable {
        case methods
        case passwordSignIn
        case signUp
        case emailEntry
        case codeEntry(isSignUp: Bool)
        case forgotPasswordEntry
        case resetPassword
    }

    private let embeddedInNavigation: Bool
    @State private var mode: Mode = .methods
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var newPassword = ""
    @State private var code = ""
    @State private var isBusy = false
    @State private var errorMessage: String?

    init(onAuthenticated: @escaping () async -> Void, onDismiss: @escaping () -> Void = {}, initialSignUp: Bool = false,
         onCreationResult: ((Bool?) -> Void)? = nil, onAuthenticationFailure: (() -> Void)? = nil, embeddedInNavigation: Bool = false) {
        self.embeddedInNavigation = embeddedInNavigation
        self.onAuthenticated = onAuthenticated
        self.onDismiss = onDismiss
        self.onCreationResult = onCreationResult
        self.onAuthenticationFailure = onAuthenticationFailure
        _mode = State(initialValue: initialSignUp ? .signUp : .methods)
    }

    @ViewBuilder
    var body: some View {
        if embeddedInNavigation { form }
        else { NavigationStack { form } }
    }

    private var form: some View {
            GeometryReader { geometry in
                ScrollView {
                    Group {
                        switch mode {
                        case .methods: methodsScreen
                        case .passwordSignIn: passwordSignInScreen
                        case .signUp: signUpScreen
                        case .emailEntry: emailEntryScreen
                        case .codeEntry(let isSignUp): codeEntryScreen(isSignUp: isSignUp)
                        case .forgotPasswordEntry: forgotPasswordEntryScreen
                        case .resetPassword: resetPasswordScreen
                        }
                    }
                    .frame(minHeight: geometry.size.height, alignment: .top)
                    .id(mode).transition(.opacity)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            .background { palette.background.ignoresSafeArea() }
            .animation(reducedMotion ? nil : .easeInOut(duration: InterfaceMotion.step), value: mode)
            .navigationTitle(mode == .signUp ? Text("Create account") : mode == .forgotPasswordEntry || mode == .resetPassword ? Text("Reset password") : Text("Sign in"))
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .tabBar)
            .toolbar {
                if mode != .methods {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Back", systemImage: "chevron.backward", action: goBack).labelStyle(.iconOnly)
                            .accessibilityIdentifier("signin.back").disabled(isBusy)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", action: onDismiss).accessibilityIdentifier("signin.close")
                }
            }
    }

    private func goBack() {
        errorMessage = nil
        switch mode {
        case .methods: onDismiss()
        case .passwordSignIn, .signUp, .emailEntry: mode = .methods
        case .codeEntry(let signUp): mode = signUp ? .signUp : .emailEntry
        case .forgotPasswordEntry: mode = .passwordSignIn
        case .resetPassword: mode = .forgotPasswordEntry
        }
    }

#if DEBUG
    static func preview(_ step: String) -> SignInView {
        var view = SignInView(onAuthenticated: {})
        let mode: Mode = switch step {
        case "password": .passwordSignIn
        case "signup": .signUp
        case "email": .emailEntry
        case "code": .codeEntry(isSignUp: true)
        case "forgot": .forgotPasswordEntry
        case "reset": .resetPassword
        default: .methods
        }
        view._mode = State(initialValue: mode)
        if step == "code" || step == "reset" { view._email = State(initialValue: "reader@example.org") }
        return view
    }
#endif

    // MARK: - Method selection

    private var methodsScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("la2.account_title")
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
                Text("la2.account_body")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
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
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(appleOutline, lineWidth: ReaderPalette.isDark(readerTheme, systemScheme: colorScheme) ? 0 : 1)
                }
                .accessibilityIdentifier("signin.apple")

                hostedAuthButton(
                    title: "Continue with Google",
                    background: palette.surfaceElevated,
                    foreground: palette.textPrimary,
                    showsGoogleMark: true
                )
                .accessibilityIdentifier("signin.google")

                Text("Google sign-in opens in your browser and returns here.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Rectangle().fill(palette.surfaceElevated).frame(height: 1)
                    Text("or")
                        .font(.footnote)
                        .foregroundStyle(palette.textSecondary)
                    Rectangle().fill(palette.surfaceElevated).frame(height: 1)
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
                        .background(palette.interactive)
                        .foregroundStyle(palette.onInteractive)
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
                .foregroundStyle(palette.textSecondary)
                .disabled(isBusy)
                .accessibilityIdentifier("signin.createAccount")

                LegalText(
                    termsURL: environment.config.termsOfUseURL,
                    privacyURL: environment.config.privacyPolicyURL
                )
            }
            .padding(.horizontal, 20)

            if let errorMessage {
                AuthErrorBanner(message: errorMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()

            Button("Keep reading as a guest") {
                onDismiss()
            }
            .font(.subheadline)
            .foregroundStyle(palette.textSecondary)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Password sign-in

    private var passwordSignInScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Welcome back")
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
                Text("Sign in with your email or username.")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 24)

            TextField("Email or username", text: $email)
                .accessibilityLabel("Email or username")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(16)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .accessibilityIdentifier("signin.identifier.field")

            SecureField("Password", text: $password)
                .accessibilityLabel("Password")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(16)
                .background(palette.surface)
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
            .background(palette.interactive)
            .foregroundStyle(palette.onInteractive)
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
            .foregroundStyle(palette.textSecondary)
            .padding(.top, 12)
            .disabled(isBusy)

            Button("Sign in with a code instead") {
                errorMessage = nil
                mode = .emailEntry
            }
            .font(.footnote)
            .foregroundStyle(palette.interactive)
            .padding(.top, 8)
            .disabled(isBusy)

            if let errorMessage {
                AuthErrorBanner(message: errorMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Sign-up

    private var signUpScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Create your account")
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
                Text("Carry your bookmarks and notes across devices.")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 24)

            VStack(spacing: 12) {
                    TextField("you@example.com", text: $email)
                .accessibilityLabel("Email")
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body)
                        .padding(16)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("signup.email.field")

                    SecureField("Password", text: $password)
                .accessibilityLabel("Password")
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body)
                        .padding(16)
                        .background(palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("signup.password.field")

                    SecureField("Repeat password", text: $confirmPassword)
                .accessibilityLabel("Repeat password")
                        .textContentType(.newPassword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.body)
                        .padding(16)
                        .background(palette.surface)
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
                    .background(palette.interactive)
                    .foregroundStyle(palette.onInteractive)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .disabled(isBusy || !signUpInputIsValid)
                    .accessibilityIdentifier("signup.submit")

                    LegalText(
                        termsURL: environment.config.termsOfUseURL,
                        privacyURL: environment.config.privacyPolicyURL
                    )

                    if let errorMessage {
                        AuthErrorBanner(message: errorMessage)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
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
                    .foregroundStyle(palette.textPrimary)
                Text("We'll send a six-digit sign-in code.")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 24)

            TextField("you@example.com", text: $email)
                .accessibilityLabel("Email")
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(16)
                .background(palette.surface)
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
            .background(palette.interactive)
            .foregroundStyle(palette.onInteractive)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .disabled(isBusy || normalizedEmail.isEmpty)
            .accessibilityIdentifier("signin.email.send")

            if let errorMessage {
                AuthErrorBanner(message: errorMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Code entry

    private func codeEntryScreen(isSignUp: Bool) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Check your email")
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
                Text("Enter the code we sent to \(email).")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            TextField("000000", text: $code)
                .accessibilityLabel("Verification code")
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .padding(16)
                .background(palette.surface)
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
            .background(palette.interactive)
            .foregroundStyle(palette.onInteractive)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .disabled(isBusy || code.count < 6)
            .accessibilityIdentifier("signin.code.verify")

            Button("Resend code") {
                Task { await resendCode(isSignUp: isSignUp) }
            }
            .font(.subheadline)
            .foregroundStyle(palette.interactive)
            .padding(.top, 12)
            .disabled(isBusy)

            if let errorMessage {
                AuthErrorBanner(message: errorMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Forgot password

    private var forgotPasswordEntryScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Reset your password")
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
                Text("We'll send a code to your email address.")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.top, 24)

            TextField("you@example.com", text: $email)
                .accessibilityIdentifier("signin.forgotEmail.field")
                .accessibilityLabel("Email")
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(16)
                .background(palette.surface)
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
            .background(palette.interactive)
            .foregroundStyle(palette.onInteractive)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .disabled(isBusy || normalizedEmail.isEmpty)

            if let errorMessage {
                AuthErrorBanner(message: errorMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private var resetPasswordScreen: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Text("Choose a new password")
                    .font(.title2.bold())
                    .foregroundStyle(palette.textPrimary)
                Text("Enter the code sent to \(email) and your new password.")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 24)

            TextField("000000", text: $code)
                .accessibilityIdentifier("signin.resetCode.field")
                .accessibilityLabel("Verification code")
                .textContentType(.oneTimeCode)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title.monospacedDigit())
                .padding(16)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter(\.isNumber).prefix(6))
                }

            SecureField("New password", text: $newPassword)
                .accessibilityIdentifier("signin.newPassword.field")
                .accessibilityLabel("New password")
                .textContentType(.newPassword)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body)
                .padding(16)
                .background(palette.surface)
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
            .background(palette.interactive)
            .foregroundStyle(palette.onInteractive)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .disabled(isBusy || code.count < 6 || newPassword.count < 8)

            if let errorMessage {
                AuthErrorBanner(message: errorMessage)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    // MARK: - Actions

    /// Opens Clerk hosted authentication (Account Portal), which completes
    /// the whole provider round-trip and activates the session. The custom
    /// OAuth handshake loses the rotating-token nonce on callback, so social
    /// sign-in that needs the browser goes through hosted auth.
    private func hostedAuthButton(
        title: String,
        background: Color,
        foreground: Color,
        showsGoogleMark: Bool = false
    ) -> some View {
        Button {
            Task {
                isBusy = true
                errorMessage = nil
                defer { isBusy = false }
                do {
                    _ = try await Clerk.shared.auth.startHostedAuth()
                    await finishAuthentication()
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
                    if showsGoogleMark { GoogleBrandMark().frame(width: 20, height: 20) }
                    Text(LocalizedStringKey(title))
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

    private var appleOutline: Color {
        ReaderPalette.isDark(readerTheme, systemScheme: colorScheme) ? .clear : palette.divider
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
                            await finishAuthentication(created: false)
                        } else {
                            errorMessage = "Sign-in needs another step. This flow is not fully supported yet."
                        }
                    case .signUp(let signUp):
                        if signUp.status == .complete {
                            await finishAuthentication(created: true)
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
                Text(LocalizedStringKey(title))
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
                await finishAuthentication(created: false)
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
                    await finishAuthentication(created: isSignUp)
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
                    await finishAuthentication(created: false)
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
            await finishAuthentication(created: true)
        } else if let signIn = Clerk.shared.auth.currentSignIn, signIn.status == .complete {
            await finishAuthentication(created: false)
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
                await finishAuthentication(created: false)
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

    private func finishAuthentication(created: Bool? = nil) async {
        onCreationResult?(created)
        await onAuthenticated()
    }
    private func present(_ error: Error) {
        onAuthenticationFailure?()
        errorMessage = AuthFailureMessage.from(error).rawValue
    }
}

#if DEBUG
struct AuthFailureCopyAuditFixture: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                TodayGreetingText(name: nil)
                    .accessibilityIdentifier("authAudit.greetingGuest")
                TodayGreetingText(name: "Original %lld %@ اسم")
                    .accessibilityIdentifier("authAudit.greetingName")
                ForEach(AuthFailureMessage.allCases, id: \.self) { message in
                    AuthErrorBanner(message: message.rawValue)
                        .accessibilityIdentifier("authAudit.error.\(message)")
                }
            }.padding(20)
        }
    }
}
#endif

struct AuthErrorBanner: View {
    let message: String

    var body: some View {
        Text(LocalizedStringKey(AuthFailureMessage.local(message).rawValue))
            .font(.footnote)
            .foregroundStyle(Theme.destructive)
            .multilineTextAlignment(.center)
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Theme.destructive.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Terms acceptance and a separate Privacy Policy notice shown on
/// the method chooser and the email sign-up screen. Terms of Use and Privacy
/// Policy are tappable links that open the public policy pages.
private struct LegalText: View {
    @Environment(\.readerPalette) private var palette
    @Environment(\.locale) private var locale
    let termsURL: URL?
    let privacyURL: URL?

    var body: some View {
        if let terms = termsURL, let privacy = privacyURL {
            legalLine(terms: terms, privacy: privacy)
        }
    }

    private func legalLine(terms: URL, privacy: URL) -> some View {
        let template = String(format: AppLocalization.string("By continuing, you agree to our %1$@. Read our %2$@.", locale: locale), locale: locale, "\u{E000}", "\u{E001}")
        var text = AttributedString()
        for character in template {
            let isTerms = character == "\u{E000}"
            let isPrivacy = character == "\u{E001}"
            var part = AttributedString(isTerms ? AppLocalization.string("Terms of Use", locale: locale) : isPrivacy ? AppLocalization.string("Privacy Policy", locale: locale) : String(character))
            part.foregroundColor = isTerms || isPrivacy ? palette.interactive : palette.textSecondary
            if isTerms { part.link = terms }
            if isPrivacy { part.link = privacy }
            text += part
        }
        return Text(text)
            .accessibilityIdentifier("signin.legal")
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

private struct GoogleBrandMark: View {
    var body: some View {
        Image("GoogleG")
            .renderingMode(.original)
            .resizable()
            .scaledToFit()
            .accessibilityHidden(true)
    }
}
