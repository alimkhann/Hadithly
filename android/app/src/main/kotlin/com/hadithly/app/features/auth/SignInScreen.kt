package com.hadithly.app.features.auth

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.ClickableText
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withAnnotation
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.hadithly.app.BuildConfig
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.core.theme.Spacing

/**
 * Custom sign-in flow (no Clerk hosted UI): Google via the system browser,
 * email + password for standard accounts, and email-code fallback. Sign-up
 * asks for an email and password only; a username is generated from the
 * email address and can be changed in Settings. Every method ends in
 * onAuthenticated, which runs the post-sign-in sync and dismisses. Mirrors
 * iOS SignInView.
 */
@Composable
fun SignInScreen(
    onAuthenticated: () -> Unit,
    onDismiss: () -> Unit,
) {
    val viewModel: SignInViewModel = viewModel()
    val state by viewModel.state.collectAsStateWithLifecycle()
    val colors = LocalHadithlyColors.current

    androidx.compose.runtime.LaunchedEffect(Unit) {
        viewModel.resetForPresentation()
    }

    // Flow completion: the custom email flow reports completion directly.
    if (state.flowComplete) {
        viewModel.consumeCompletion()
        onAuthenticated()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = Spacing.sm, vertical = Spacing.sm),
                horizontalArrangement = Arrangement.End,
            ) {
                TextButton(onClick = onDismiss) {
                    Text("Close", color = colors.textSecondary)
                }
            }

            when (state.mode) {
                SignInMode.METHODS -> MethodsScreen(
                    state = state,
                    onGoogle = { viewModel.signInWithGoogle() },
                    onPasswordSignIn = { viewModel.showPasswordSignIn() },
                    onSignUp = { viewModel.showSignUp() },
                )
                SignInMode.PASSWORD_SIGN_IN -> PasswordSignInScreen(
                    state = state,
                    onIdentifierChanged = { viewModel.setIdentifier(it) },
                    onPasswordChanged = { viewModel.setPassword(it) },
                    onSignIn = { viewModel.signInWithPassword() },
                    onForgotPassword = { viewModel.showForgotPassword() },
                    onUseCode = { viewModel.showEmailEntry() },
                )
                SignInMode.SIGN_UP -> SignUpScreen(
                    state = state,
                    onEmailChanged = { viewModel.setEmail(it) },
                    onPasswordChanged = { viewModel.setPassword(it) },
                    onConfirmPasswordChanged = { viewModel.setConfirmPassword(it) },
                    onSubmit = { viewModel.submitSignUp() },
                )
                SignInMode.EMAIL_ENTRY -> EmailEntryScreen(
                    state = state,
                    onEmailChanged = { viewModel.setEmail(it) },
                    onSendCode = { viewModel.startEmailFlow() },
                )
                SignInMode.CODE_ENTRY -> CodeEntryScreen(
                    state = state,
                    onCodeChanged = { viewModel.setCode(it) },
                    onVerify = { viewModel.submitCode() },
                    onResend = { viewModel.resendCode() },
                    onBack = { viewModel.backToMethods() },
                )
                SignInMode.FORGOT_PASSWORD_ENTRY -> ForgotPasswordScreen(
                    state = state,
                    onEmailChanged = { viewModel.setEmail(it) },
                    onSendCode = { viewModel.startPasswordReset() },
                )
                SignInMode.RESET_PASSWORD -> ResetPasswordScreen(
                    state = state,
                    onCodeChanged = { viewModel.setCode(it) },
                    onNewPasswordChanged = { viewModel.setNewPassword(it) },
                    onSubmit = { viewModel.submitPasswordReset() },
                )
            }
        }
    }
}

@Composable
private fun AuthHeader(title: String, subtitle: String) {
    val colors = LocalHadithlyColors.current
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = title,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
        )
        Text(
            text = subtitle,
            fontSize = 15.sp,
            color = colors.textSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(top = Spacing.sm)
                .padding(horizontal = Spacing.sm),
        )
    }
}

@Composable
private fun MethodsScreen(
    state: SignInUiState,
    onGoogle: () -> Unit,
    onPasswordSignIn: () -> Unit,
    onSignUp: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(Spacing.xl))
        AuthHeader(
            title = "Sync your reading",
            subtitle = "Guests can read everything. An account just carries your bookmarks and notes across devices.",
        )

        Spacer(modifier = Modifier.weight(1f))

        Column(verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
            // Apple sign-in does not exist on Android; Google carries OAuth.
            ProviderButton(
                title = "Continue with Google",
                container = colors.surfaceElevated,
                content = colors.textPrimary,
                busy = state.isBusy,
                onClick = onGoogle,
            )
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.md),
                modifier = Modifier.padding(vertical = Spacing.xs),
            ) {
                Box(modifier = Modifier.weight(1f).height(1.dp).background(colors.surfaceElevated))
                Text("or", fontSize = 13.sp, color = colors.textSecondary)
                Box(modifier = Modifier.weight(1f).height(1.dp).background(colors.surfaceElevated))
            }
            AccentButton(
                text = "Continue with email",
                onClick = onPasswordSignIn,
                enabled = !state.isBusy,
            )
            TextButton(onClick = onSignUp, enabled = !state.isBusy) {
                Text("Create account", color = colors.textSecondary, fontSize = 15.sp)
            }

            LegalLine(modifier = Modifier.padding(top = Spacing.sm))
        }

        state.errorMessage?.let { message ->
            ErrorBanner(message = message, modifier = Modifier.padding(top = Spacing.lg))
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun PasswordSignInScreen(
    state: SignInUiState,
    onIdentifierChanged: (String) -> Unit,
    onPasswordChanged: (String) -> Unit,
    onSignIn: () -> Unit,
    onForgotPassword: () -> Unit,
    onUseCode: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(Spacing.xl))
        AuthHeader(title = "Welcome back", subtitle = "Sign in with your email or username.")

        Spacer(modifier = Modifier.height(Spacing.xl))

        AuthTextField(
            value = state.identifier,
            onValueChange = onIdentifierChanged,
            placeholder = "Email or username",
            keyboardType = KeyboardType.Email,
            colors = colors,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        AuthTextField(
            value = state.password,
            onValueChange = onPasswordChanged,
            placeholder = "Password",
            keyboardType = KeyboardType.Password,
            isPassword = true,
            colors = colors,
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        AccentButton(
            text = "Sign in",
            onClick = onSignIn,
            enabled = !state.isBusy && state.identifier.isNotBlank() && state.password.isNotEmpty(),
            busy = state.isBusy,
        )

        TextButton(onClick = onForgotPassword, enabled = !state.isBusy) {
            Text("Forgot password?", color = colors.textSecondary, fontSize = 15.sp)
        }
        TextButton(onClick = onUseCode, enabled = !state.isBusy) {
            Text("Sign in with a code instead", color = colors.accent, fontSize = 13.sp)
        }

        state.errorMessage?.let { message ->
            ErrorBanner(message = message, modifier = Modifier.padding(top = Spacing.lg))
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun SignUpScreen(
    state: SignInUiState,
    onEmailChanged: (String) -> Unit,
    onPasswordChanged: (String) -> Unit,
    onConfirmPasswordChanged: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val inputValid = state.email.isNotBlank() &&
        state.password.length >= 8 &&
        state.confirmPassword == state.password
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(Spacing.xl))
        AuthHeader(title = "Create your account", subtitle = "Carry your bookmarks and notes across devices.")

        Spacer(modifier = Modifier.height(Spacing.xl))

        AuthTextField(
            value = state.email,
            onValueChange = onEmailChanged,
            placeholder = "you@example.com",
            keyboardType = KeyboardType.Email,
            colors = colors,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        AuthTextField(
            value = state.password,
            onValueChange = onPasswordChanged,
            placeholder = "Password",
            keyboardType = KeyboardType.Password,
            isPassword = true,
            colors = colors,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        AuthTextField(
            value = state.confirmPassword,
            onValueChange = onConfirmPasswordChanged,
            placeholder = "Repeat password",
            keyboardType = KeyboardType.Password,
            isPassword = true,
            colors = colors,
        )

        if (state.confirmPassword.isNotEmpty() && state.confirmPassword != state.password) {
            Text(
                text = "Passwords do not match.",
                fontSize = 13.sp,
                color = colors.destructive,
                modifier = Modifier.padding(top = Spacing.sm),
            )
        }

        Spacer(modifier = Modifier.height(Spacing.lg))

        AccentButton(
            text = "Create account",
            onClick = onSubmit,
            enabled = !state.isBusy && inputValid,
            busy = state.isBusy,
        )

        LegalLine(modifier = Modifier.padding(top = Spacing.md))

        state.errorMessage?.let { message ->
            ErrorBanner(message = message, modifier = Modifier.padding(top = Spacing.lg))
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

@Composable
private fun EmailEntryScreen(
    state: SignInUiState,
    onEmailChanged: (String) -> Unit,
    onSendCode: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(Spacing.xl))
        AuthHeader(title = "What's your email?", subtitle = "We'll send a six-digit sign-in code.")

        Spacer(modifier = Modifier.height(Spacing.xl))

        AuthTextField(
            value = state.email,
            onValueChange = onEmailChanged,
            placeholder = "you@example.com",
            keyboardType = KeyboardType.Email,
            colors = colors,
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        AccentButton(
            text = "Send code",
            onClick = onSendCode,
            enabled = !state.isBusy && state.email.isNotBlank(),
            busy = state.isBusy,
        )

        state.errorMessage?.let { message ->
            ErrorBanner(message = message, modifier = Modifier.padding(top = Spacing.lg))
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun CodeEntryScreen(
    state: SignInUiState,
    onCodeChanged: (String) -> Unit,
    onVerify: () -> Unit,
    onResend: () -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(Spacing.xl))
        AuthHeader(title = "Check your email", subtitle = "Enter the code we sent to ${state.email}.")

        Spacer(modifier = Modifier.height(Spacing.xl))

        AuthTextField(
            value = state.code,
            onValueChange = onCodeChanged,
            placeholder = "000000",
            keyboardType = KeyboardType.NumberPassword,
            colors = colors,
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        AccentButton(
            text = "Verify",
            onClick = onVerify,
            enabled = !state.isBusy && state.code.length >= 6,
            busy = state.isBusy,
        )

        TextButton(onClick = onResend, enabled = !state.isBusy) {
            Text("Resend code", color = colors.accent, fontSize = 15.sp)
        }
        TextButton(onClick = onBack, enabled = !state.isBusy) {
            Text("Use a different email", color = colors.textSecondary, fontSize = 15.sp)
        }

        state.errorMessage?.let { message ->
            ErrorBanner(message = message, modifier = Modifier.padding(top = Spacing.lg))
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun ForgotPasswordScreen(
    state: SignInUiState,
    onEmailChanged: (String) -> Unit,
    onSendCode: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(Spacing.xl))
        AuthHeader(title = "Reset your password", subtitle = "We'll send a code to your email address.")

        Spacer(modifier = Modifier.height(Spacing.xl))

        AuthTextField(
            value = state.email,
            onValueChange = onEmailChanged,
            placeholder = "you@example.com",
            keyboardType = KeyboardType.Email,
            colors = colors,
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        AccentButton(
            text = "Send code",
            onClick = onSendCode,
            enabled = !state.isBusy && state.email.isNotBlank(),
            busy = state.isBusy,
        )

        state.errorMessage?.let { message ->
            ErrorBanner(message = message, modifier = Modifier.padding(top = Spacing.lg))
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

@Composable
private fun ResetPasswordScreen(
    state: SignInUiState,
    onCodeChanged: (String) -> Unit,
    onNewPasswordChanged: (String) -> Unit,
    onSubmit: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(Spacing.xl))
        AuthHeader(
            title = "Choose a new password",
            subtitle = "Enter the code sent to ${state.email} and your new password.",
        )

        Spacer(modifier = Modifier.height(Spacing.xl))

        AuthTextField(
            value = state.code,
            onValueChange = onCodeChanged,
            placeholder = "000000",
            keyboardType = KeyboardType.NumberPassword,
            colors = colors,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        AuthTextField(
            value = state.newPassword,
            onValueChange = onNewPasswordChanged,
            placeholder = "New password",
            keyboardType = KeyboardType.Password,
            isPassword = true,
            colors = colors,
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        AccentButton(
            text = "Set new password",
            onClick = onSubmit,
            enabled = !state.isBusy && state.code.length >= 6 && state.newPassword.length >= 8,
            busy = state.isBusy,
        )

        state.errorMessage?.let { message ->
            ErrorBanner(message = message, modifier = Modifier.padding(top = Spacing.lg))
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

/**
 * "By continuing, you agree to our Terms of Use and Privacy Policy." shown on
 * the method chooser and the email sign-up screen. Terms of Use and Privacy
 * Policy are tappable links that open the public policy pages.
 */
@Composable
private fun LegalLine(modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    val uriHandler = LocalUriHandler.current
    val termsUrl = BuildConfig.TERMS_OF_USE_URL
    val privacyUrl = BuildConfig.PRIVACY_POLICY_URL

    val annotated = remember(termsUrl, privacyUrl) {
        buildAnnotatedString {
            withStyle(SpanStyle(color = colors.textSecondary)) {
                append("By continuing, you agree to our ")
            }
            withAnnotation("URL", termsUrl) {
                withStyle(SpanStyle(color = colors.accent)) { append("Terms of Use") }
            }
            withStyle(SpanStyle(color = colors.textSecondary)) { append(" and ") }
            withAnnotation("URL", privacyUrl) {
                withStyle(SpanStyle(color = colors.accent)) { append("Privacy Policy") }
            }
            withStyle(SpanStyle(color = colors.textSecondary)) { append(".") }
        }
    }

    ClickableText(
        text = annotated,
        style = androidx.compose.ui.text.TextStyle(
            fontSize = 12.sp,
            textAlign = TextAlign.Center,
            lineHeight = 16.sp,
        ),
        modifier = modifier.padding(horizontal = Spacing.sm),
        onClick = { offset ->
            annotated.getStringAnnotations("URL", offset, offset)
                .firstOrNull()
                ?.let { uriHandler.openUri(it.item) }
        },
    )
}

@Composable
private fun AuthTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    keyboardType: KeyboardType,
    colors: com.hadithly.app.core.theme.HadithlyColors,
    isPassword: Boolean = false,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        placeholder = { Text(placeholder, color = colors.textSecondary) },
        singleLine = true,
        visualTransformation = if (isPassword) {
            PasswordVisualTransformation()
        } else {
            androidx.compose.ui.text.input.VisualTransformation.None
        },
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType),
        shape = RoundedCornerShape(12.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.surfaceElevated,
            focusedTextColor = colors.textPrimary,
            unfocusedTextColor = colors.textPrimary,
            cursorColor = colors.accent,
        ),
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun ProviderButton(
    title: String,
    container: Color,
    content: Color,
    busy: Boolean,
    onClick: () -> Unit,
) {
    Button(
        onClick = onClick,
        enabled = !busy,
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = container, contentColor = content),
        modifier = Modifier.fillMaxWidth().height(52.dp),
    ) {
        if (busy) {
            CircularProgressIndicator(color = content, strokeWidth = 2.dp)
        } else {
            Text(title, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun AccentButton(
    text: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
    busy: Boolean = false,
) {
    val colors = LocalHadithlyColors.current
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = Color.Black),
        modifier = Modifier.fillMaxWidth().height(52.dp),
    ) {
        if (busy) {
            CircularProgressIndicator(color = Color.Black, strokeWidth = 2.dp)
        } else {
            Text(text, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun ErrorBanner(message: String, modifier: Modifier = Modifier) {
    Text(
        text = message,
        color = Color(0xFFFF6B6B),
        fontSize = 14.sp,
        textAlign = TextAlign.Center,
        modifier = modifier
            .fillMaxWidth()
            .background(Color(0xFFFF6B6B).copy(alpha = 0.12f), RoundedCornerShape(10.dp))
            .padding(vertical = 10.dp, horizontal = 12.dp),
    )
}
