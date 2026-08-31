package com.hadithly.app.features.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.clerk.api.Clerk
import com.clerk.api.auth.types.VerificationType
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.network.serialization.errorMessage
import com.clerk.api.network.serialization.flatMap
import com.clerk.api.network.serialization.onFailure
import com.clerk.api.network.serialization.onSuccess
import com.clerk.api.signin.SignIn
import com.clerk.api.signin.sendCode
import com.clerk.api.signin.verifyCode
import com.clerk.api.signup.SignUp
import com.clerk.api.signup.sendCode
import com.clerk.api.signup.update
import com.clerk.api.signup.verifyCode
import com.clerk.api.sso.OAuthProvider
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class SignInMode { METHODS, EMAIL_ENTRY, CODE_ENTRY }

data class SignInUiState(
    val mode: SignInMode = SignInMode.METHODS,
    val email: String = "",
    val code: String = "",
    val isSignUp: Boolean = false,
    val isBusy: Boolean = false,
    val errorMessage: String? = null,
    val flowComplete: Boolean = false,
)

/**
 * Email-code sign-in with automatic sign-up fallback, plus Google OAuth.
 * The Clerk instance may still require username + password at sign-up;
 * when it does, generated values are filled so the UI never asks for them
 * (same approach as iOS SignInView.fulfillMissingRequirements).
 */
class SignInViewModel : ViewModel() {

    private val _state = MutableStateFlow(SignInUiState())
    val state: StateFlow<SignInUiState> = _state

    /** The screen reacts to completion once, then resets the flag. */
    fun consumeCompletion() {
        _state.update { it.copy(flowComplete = false) }
    }

    fun setEmail(email: String) = _state.update { it.copy(email = email, errorMessage = null) }

    fun setCode(code: String) =
        _state.update { it.copy(code = code.filter(Char::isDigit).take(6), errorMessage = null) }

    fun showEmailEntry() = _state.update { it.copy(mode = SignInMode.EMAIL_ENTRY, errorMessage = null) }

    fun backToMethods() =
        _state.update { it.copy(mode = SignInMode.METHODS, email = "", code = "", errorMessage = null) }

    fun signInWithGoogle() {
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            Clerk.auth.signInWithOAuth(OAuthProvider.GOOGLE)
                .onSuccess { result -> finishOAuth(result) }
                .onFailure(::presentError)
            _state.update { it.copy(isBusy = false) }
        }
    }

    fun startEmailFlow() {
        val email = _state.value.email.trim().lowercase()
        viewModelScope.launch {
            _state.update { it.copy(isBusy = true, errorMessage = null) }
            Clerk.auth.signInWithOtp { this.email = email }
                .onSuccess {
                    _state.update { it.copy(mode = SignInMode.CODE_ENTRY, isSignUp = false) }
                }
                .onFailure { failure ->
                    // No account yet — continue as sign-up with the same address.
                    if (failure.isAccountMissing()) {
                        Clerk.auth.signUp { this.email = email }
                            .flatMap { signUp -> signUp.sendCode { this.email = email } }
                            .onSuccess {
                                _state.update { it.copy(mode = SignInMode.CODE_ENTRY, isSignUp = true) }
                            }
                            .onFailure(::presentError)
                    } else {
                        presentError(failure)
                    }
                }
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
                    .flatMap { updated -> fulfillMissingRequirementsIfNeeded(updated) }
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

    private fun finishOAuth(result: com.clerk.api.sso.OAuthResult) {
        val signIn = result.signIn
        if (signIn?.status == SignIn.Status.COMPLETE) {
            setActiveAndFinish(signIn.createdSessionId)
        } else {
            _state.update {
                it.copy(errorMessage = "Sign-in needs another step. This flow is not fully supported yet.")
            }
        }
    }

    private fun setActiveAndFinish(createdSessionId: String?) {
        if (createdSessionId == null) {
            _state.update { it.copy(flowComplete = true) }
            return
        }
        viewModelScope.launch {
            Clerk.auth.setActive(sessionId = createdSessionId)
                .onSuccess { _state.update { it.copy(flowComplete = true) } }
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

    /**
     * Hadithly never asks for passwords or usernames in its UI. If the
     * Clerk instance still requires them at sign-up, fill generated values
     * so email-code sign-up completes without user-facing fields.
     */
    private suspend fun fulfillMissingRequirementsIfNeeded(signUp: SignUp): ClerkResult<SignUp, com.clerk.api.network.model.error.ClerkErrorResponse> {
        if (signUp.status != SignUp.Status.MISSING_REQUIREMENTS) return ClerkResult.success(signUp)
        val suffix = UUID.randomUUID().toString().take(8).lowercase().replace("-", "0")
        val username = "reader_$suffix"
        val password = UUID.randomUUID().toString().replace("-", "").take(24) + "9xK"
        return signUp.update {
            this.password = password
            this.username = username
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
