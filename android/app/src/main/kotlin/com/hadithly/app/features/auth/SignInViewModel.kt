package com.hadithly.app.features.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clerk.api.Clerk
import com.clerk.api.auth.HostedAuthMode
import com.clerk.api.auth.types.VerificationType
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.network.serialization.errorMessage
import com.clerk.api.network.serialization.flatMap
import com.clerk.api.network.serialization.onFailure
import com.clerk.api.network.serialization.onSuccess
import com.clerk.api.signin.SignIn
import com.clerk.api.signin.resetPassword
import com.clerk.api.signin.sendCode
import com.clerk.api.signin.sendResetPasswordCode
import com.clerk.api.signin.verifyCode
import com.clerk.api.signup.SignUp
import com.clerk.api.signup.sendCode
import com.clerk.api.signup.verifyCode
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class SignInMode {
    METHODS,
    PASSWORD_SIGN_IN,
    SIGN_UP,
    EMAIL_ENTRY,
    CODE_ENTRY,
    FORGOT_PASSWORD_ENTRY,
    RESET_PASSWORD,
}

data class SignInUiState(
    val mode: SignInMode = SignInMode.METHODS,
    val identifier: String = "",
    val email: String = "",
    val password: String = "",
    val confirmPassword: String = "",
    val newPassword: String = "",
    val code: String = "",
    val isSignUp: Boolean = false,
    val isBusy: Boolean = false,
    val errorMessage: String? = null,
    val flowComplete: Boolean = false,
)

/**
 * Standard email + password auth with Apple/Google parity where the platform
 * supports it. Sign-up requires an email address (verified with a one-time
 * code) and a password; a username is generated from the email address and
 * can be changed later in Settings. Sign-in accepts the email address or the
 * username with the password; email-code sign-in stays as a fallback and
 * password reset uses the emailed code. Every path ends in flowComplete,
 * which runs the post-sign-in sync and dismisses.
 */
class SignInViewModel : ViewModel() {

    private val _state = MutableStateFlow(SignInUiState())
    val state: StateFlow<SignInUiState> = _state

    /** The screen reacts to completion once, then resets the flag. */
    fun consumeCompletion() {
        _state.update { it.copy(flowComplete = false) }
    }

    /**
     * Starts every presentation from the method list. The ViewModel is scoped
     * to the Activity, so without this a reopened sheet would resume a stale
     * mid-flow state (e.g. the code screen) after sign-out.
     */
    fun resetForPresentation() {
        _state.value = SignInUiState()
    }

    fun setIdentifier(identifier: String) =
        _state.update { it.copy(identifier = identifier, errorMessage = null) }

    fun setEmail(email: String) = _state.update { it.copy(email = email, errorMessage = null) }

    fun setPassword(password: String) =
        _state.update { it.copy(password = password, errorMessage = null) }

    fun setConfirmPassword(password: String) =
        _state.update { it.copy(confirmPassword = password, errorMessage = null) }

    fun setNewPassword(password: String) =
        _state.update { it.copy(newPassword = password, errorMessage = null) }

    fun setCode(code: String) =
        _state.update { it.copy(code = code.filter(Char::isDigit).take(6), errorMessage = null) }

    fun showPasswordSignIn() =
        _state.update {
            it.copy(
                mode = SignInMode.PASSWORD_SIGN_IN,
                identifier = "",
                password = "",
                errorMessage = null,
            )
        }

    fun showSignUp() =
        _state.update {
            it.copy(
                mode = SignInMode.SIGN_UP,
                email = "",
                password = "",
                confirmPassword = "",
                errorMessage = null,
            )
        }

    fun showEmailEntry() = _state.update { it.copy(mode = SignInMode.EMAIL_ENTRY, errorMessage = null) }

    fun showForgotPassword() =
        _state.update { it.copy(mode = SignInMode.FORGOT_PASSWORD_ENTRY, errorMessage = null) }

    fun backToMethods() =
        _state.update {
            it.copy(
                mode = SignInMode.METHODS,
                identifier = "",
                email = "",
                password = "",
                confirmPassword = "",
                newPassword = "",
                code = "",
                errorMessage = null,
            )
        }

    /**
     * Google runs through Clerk hosted authentication (Account Portal). The
     * browser-based OAuth redirect handshake loses the rotating-token nonce
     * on the callback, so the custom flow cannot complete; hosted auth
     * returns the activated session directly.
     */
    fun signInWithGoogle() {
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            Clerk.auth.startHostedAuth(HostedAuthMode.SIGN_IN)
                .onSuccess {
                    _state.update { it.copy(isBusy = false, flowComplete = true) }
                }
                .onFailure(::presentError)
        }
    }

    fun signInWithPassword() {
        val current = _state.value
        val identifier = current.identifier.trim().lowercase()
        if (identifier.isEmpty() || current.password.isEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            Clerk.auth.signInWithPassword {
                this.identifier = identifier
                this.password = current.password
            }
                .onSuccess { signIn -> finishSignIn(signIn) }
                .onFailure { failure ->
                    _state.update {
                        if (failure.isAccountMissing()) {
                            it.copy(
                                isBusy = false,
                                errorMessage = "No account found for that identifier. Create an account first.",
                            )
                        } else {
                            it.copy(isBusy = false, errorMessage = failure.errorMessage)
                        }
                    }
                }
        }
    }

    fun submitSignUp() {
        val current = _state.value
        val email = current.email.trim().lowercase()
        if (email.isEmpty() || current.password.length < 8) return
        if (current.confirmPassword != current.password) {
            _state.update { it.copy(errorMessage = "Passwords do not match.") }
            return
        }
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            createSignUp(email = email, password = current.password, username = generatedUsername(email))
        }
    }

    /**
     * Creates the sign-up with a generated username (Clerk usernames must be
     * unique), appending a numeric suffix and retrying once if the derived
     * name is already taken, then moves to the email-code step.
     */
    private fun createSignUp(email: String, password: String, username: String, retried: Boolean = false) {
        viewModelScope.launch {
            Clerk.auth.signUp {
                this.email = email
                this.username = username
                this.password = password
            }
                .flatMap { signUp -> signUp.sendCode { this.email = email } }
                .onSuccess {
                    _state.update { it.copy(isBusy = false, mode = SignInMode.CODE_ENTRY, isSignUp = true) }
                }
                .onFailure { failure ->
                    val usernameTaken = failure.errorMessage.contains("username", ignoreCase = true) &&
                        failure.errorMessage.contains("already", ignoreCase = true) ||
                        failure.errorMessage.contains("form_username_in_use", ignoreCase = true)
                    if (usernameTaken && !retried) {
                        createSignUp(
                            email = email,
                            password = password,
                            username = "$username${(100..999).random()}",
                            retried = true,
                        )
                    } else {
                        presentError(failure)
                    }
                }
        }
    }

    /**
     * The user never types a username: it is derived from the email local
     * part (letters and digits only, at least 3 characters) so OAuth-created
     * and password-created accounts stay consistent. Changeable in Settings.
     */
    private fun generatedUsername(email: String): String {
        val base = email.substringBefore('@')
            .filter { it.isLetterOrDigit() }
            .lowercase()
            .take(24)
        return if (base.length >= 3) base else "reader${(100..999).random()}"
    }

    fun startEmailFlow() {
        val email = _state.value.email.trim().lowercase()
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            Clerk.auth.signInWithOtp { this.email = email }
                .onSuccess {
                    _state.update { it.copy(isBusy = false, mode = SignInMode.CODE_ENTRY, isSignUp = false) }
                }
                .onFailure { failure ->
                    if (failure.isAccountMissing()) {
                        _state.update {
                            it.copy(
                                isBusy = false,
                                errorMessage = "No account found for that email. Create an account first.",
                            )
                        }
                    } else {
                        presentError(failure)
                    }
                }
            _state.update { it.copy(isBusy = false) }
        }
    }

    fun startPasswordReset() {
        val email = _state.value.email.trim().lowercase()
        if (email.isEmpty()) return
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            Clerk.auth.signIn { this.email = email }
                .flatMap { signIn -> signIn.sendResetPasswordCode { this.email = email } }
                .onSuccess {
                    _state.update { it.copy(isBusy = false, mode = SignInMode.RESET_PASSWORD) }
                }
                .onFailure(::presentError)
        }
    }

    fun submitPasswordReset() {
        val current = _state.value
        if (current.code.length < 6 || current.newPassword.length < 8) return
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            val signIn = Clerk.auth.currentSignIn
            if (signIn == null) {
                _state.update {
                    it.copy(isBusy = false, errorMessage = "The reset session expired. Please start again.")
                }
                return@launch
            }
            signIn.verifyCode(current.code)
                .flatMap { updated -> updated.resetPassword(current.newPassword) }
                .onSuccess { updated ->
                    if (updated.status == SignIn.Status.COMPLETE) {
                        setActiveAndFinish(updated.createdSessionId)
                    } else {
                        _state.update {
                            it.copy(isBusy = false, errorMessage = "Could not reset the password. Please try again.")
                        }
                    }
                }
                .onFailure(::presentError)
            _state.update { it.copy(isBusy = false) }
        }
    }

    fun submitCode() {
        val current = _state.value
        val code = current.code
        if (code.length < 6) return
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            if (current.isSignUp) {
                val signUp = Clerk.auth.currentSignUp
                if (signUp == null) {
                    _state.update {
                        it.copy(isBusy = false, errorMessage = "The sign-up session expired. Please start again.")
                    }
                    return@launch
                }
                signUp.verifyCode(code, VerificationType.EMAIL)
                    .onSuccess { updated ->
                        if (updated.status == SignUp.Status.COMPLETE) {
                            setActiveAndFinish(updated.createdSessionId)
                        } else {
                            _state.update {
                                it.copy(isBusy = false, errorMessage = "Sign-up could not be completed. Please try again.")
                            }
                        }
                    }
                    .onFailure { failure ->
                        if (failure.isAlreadyVerified()) {
                            handleAlreadyVerified(isSignUp = true)
                        } else {
                            presentError(failure)
                        }
                    }
            } else {
                val signIn = Clerk.auth.currentSignIn
                if (signIn == null) {
                    _state.update {
                        it.copy(isBusy = false, errorMessage = "The sign-in session expired. Please start again.")
                    }
                    return@launch
                }
                signIn.verifyCode(code)
                    .onSuccess { updated ->
                        if (updated.status == SignIn.Status.COMPLETE) {
                            setActiveAndFinish(updated.createdSessionId)
                        }
                    }
                    .onFailure { failure ->
                        if (failure.isAlreadyVerified()) {
                            handleAlreadyVerified(isSignUp = false)
                        } else {
                            presentError(failure)
                        }
                    }
            }
            _state.update { it.copy(isBusy = false) }
        }
    }

    fun resendCode() {
        val email = _state.value.email.trim().lowercase()
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            if (_state.value.isSignUp) {
                Clerk.auth.currentSignUp?.sendCode { this.email = email }
                    ?.onFailure(::presentError)
            } else {
                Clerk.auth.currentSignIn?.sendCode { this.email = email }
                    ?.onFailure(::presentError)
            }
            _state.update { it.copy(isBusy = false) }
        }
    }

    private fun finishSignIn(signIn: SignIn) {
        if (signIn.status == SignIn.Status.COMPLETE) {
            setActiveAndFinish(signIn.createdSessionId)
        } else {
            _state.update {
                it.copy(isBusy = false, errorMessage = "Sign-in needs another step. Please try again.")
            }
        }
    }

    private fun setActiveAndFinish(createdSessionId: String?) {
        if (createdSessionId == null) {
            _state.update { it.copy(isBusy = false, flowComplete = true) }
            return
        }
        viewModelScope.launch {
            Clerk.auth.setActive(sessionId = createdSessionId)
                .onSuccess { _state.update { it.copy(isBusy = false, flowComplete = true) } }
                .onFailure { failure ->
                    _state.update { it.copy(isBusy = false, errorMessage = failure.errorMessage) }
                }
        }
    }

    /**
     * A retry after the verification already succeeded (e.g. the completion
     * step was interrupted). If the flow is complete, finish it.
     */
    private fun handleAlreadyVerified(isSignUp: Boolean) {
        if (isSignUp) {
            val signUp = Clerk.auth.currentSignUp
            if (signUp?.status == SignUp.Status.COMPLETE) {
                setActiveAndFinish(signUp.createdSessionId)
                return
            }
        } else {
            val signIn = Clerk.auth.currentSignIn
            if (signIn?.status == SignIn.Status.COMPLETE) {
                setActiveAndFinish(signIn.createdSessionId)
                return
            }
        }
        _state.update {
            it.copy(isBusy = false, errorMessage = "This code was already used. Please request a new one.")
        }
    }

    private fun presentError(failure: ClerkResult.Failure<com.clerk.api.network.model.error.ClerkErrorResponse>) {
        _state.update { it.copy(isBusy = false, errorMessage = failure.errorMessage) }
    }

    private fun ClerkResult.Failure<com.clerk.api.network.model.error.ClerkErrorResponse>.isAccountMissing(): Boolean =
        errorMessage.contains("not found", ignoreCase = true) ||
            errorMessage.contains("form_identifier_not_found", ignoreCase = true) ||
            errorMessage.contains("couldn't find", ignoreCase = true) ||
            errorMessage.contains("could not find", ignoreCase = true) ||
            errorMessage.contains("doesn't exist", ignoreCase = true)

    private fun ClerkResult.Failure<com.clerk.api.network.model.error.ClerkErrorResponse>.isAlreadyVerified(): Boolean =
        errorMessage.contains("verification_already_verified", ignoreCase = true) ||
            errorMessage.contains("already verified", ignoreCase = true)
}
