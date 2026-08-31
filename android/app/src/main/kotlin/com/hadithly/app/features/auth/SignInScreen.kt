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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.hadithly.app.core.theme.LocalHadithlyColors

/**
 * Custom sign-in flow (no Clerk hosted UI): Google via the system browser
 * and email via a one-time code. Every method ends in onAuthenticated, which
 * runs the post-sign-in sync and dismisses. Mirrors iOS SignInView.
 */
@Composable
fun SignInScreen(
    onAuthenticated: () -> Unit,
    onDismiss: () -> Unit,
) {
    val viewModel: SignInViewModel = viewModel()
    val state by viewModel.state.collectAsStateWithLifecycle()
    val colors = LocalHadithlyColors.current

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
                    .padding(horizontal = 8.dp, vertical = 8.dp),
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
                    onEmail = { viewModel.showEmailEntry() },
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
            }
        }
    }
}

@Composable
private fun MethodsScreen(
    state: SignInUiState,
    onGoogle: () -> Unit,
    onEmail: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = "Sync your reading",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
        )
        Text(
            text = "Guests can read everything. An account just carries your bookmarks and notes across devices.",
            fontSize = 15.sp,
            color = colors.textSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp, start = 8.dp, end = 8.dp),
        )

        Spacer(modifier = Modifier.weight(1f))

        Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
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
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                modifier = Modifier.padding(vertical = 4.dp),
            ) {
                Box(modifier = Modifier.weight(1f).height(1.dp).background(colors.surfaceElevated))
                Text("or", fontSize = 13.sp, color = colors.textSecondary)
                Box(modifier = Modifier.weight(1f).height(1.dp).background(colors.surfaceElevated))
            }
            AccentButton(
                text = "Continue with email",
                onClick = onEmail,
                enabled = !state.isBusy,
            )
        }

        state.errorMessage?.let { message ->
            ErrorBanner(message = message, modifier = Modifier.padding(top = 16.dp))
        }

        Spacer(modifier = Modifier.weight(1f))
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
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = "What's your email?",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
        )
        Text(
            text = "We'll send a six-digit sign-in code.",
            fontSize = 15.sp,
            color = colors.textSecondary,
            modifier = Modifier.padding(top = 8.dp),
        )

        Spacer(modifier = Modifier.height(24.dp))

        OutlinedTextField(
            value = state.email,
            onValueChange = onEmailChanged,
            placeholder = { Text("you@example.com", color = colors.textSecondary) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email),
            shape = RoundedCornerShape(12.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = colors.accent,
                unfocusedBorderColor = colors.surfaceElevated,
                focusedTextColor = colors.textPrimary,
                unfocusedTextColor = colors.textPrimary,
                cursorColor = colors.accent,
                focusedContainerColor = colors.surface,
                unfocusedContainerColor = colors.surface,
            ),
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(modifier = Modifier.height(16.dp))

        AccentButton(
            text = "Send code",
            onClick = onSendCode,
            enabled = !state.isBusy && state.email.isNotBlank(),
            busy = state.isBusy,
        )

        state.errorMessage?.let { message ->
            ErrorBanner(message = message, modifier = Modifier.padding(top = 16.dp))
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
        Spacer(modifier = Modifier.height(24.dp))
        Text(
            text = "Check your email",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
        )
        Text(
            text = "Enter the code we sent to ${state.email}.",
            fontSize = 15.sp,
            color = colors.textSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 8.dp),
        )

        Spacer(modifier = Modifier.height(24.dp))

        OutlinedTextField(
            value = state.code,
            onValueChange = onCodeChanged,
            placeholder = { Text("000000", color = colors.textSecondary) },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
            shape = RoundedCornerShape(12.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = colors.accent,
                unfocusedBorderColor = colors.surfaceElevated,
                focusedTextColor = colors.textPrimary,
                unfocusedTextColor = colors.textPrimary,
                cursorColor = colors.accent,
                focusedContainerColor = colors.surface,
                unfocusedContainerColor = colors.surface,
            ),
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(modifier = Modifier.height(16.dp))

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
            ErrorBanner(message = message, modifier = Modifier.padding(top = 16.dp))
        }

        Spacer(modifier = Modifier.weight(1f))
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
        enabled = enabled && !busy,
        shape = RoundedCornerShape(14.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = colors.accent,
            contentColor = Color.Black,
        ),
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp),
    ) {
        if (busy) {
            CircularProgressIndicator(color = Color.Black, modifier = Modifier.height(22.dp).width(22.dp), strokeWidth = 2.dp)
        } else {
            Text(text, fontWeight = FontWeight.Bold, fontSize = 16.sp)
        }
    }
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
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp),
    ) {
        Text(title, fontWeight = FontWeight.Bold, fontSize = 16.sp)
    }
}

@Composable
private fun ErrorBanner(message: String, modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    Text(
        text = message,
        fontSize = 13.sp,
        color = colors.destructive,
        textAlign = TextAlign.Center,
        modifier = modifier
            .fillMaxWidth()
            .background(
                colors.destructive.copy(alpha = 0.12f),
                RoundedCornerShape(10.dp),
            )
            .padding(12.dp),
    )
}
