package com.hadithly.app.core.theme

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.runtime.remember
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp

// AnimatedVisibility obeys the platform MotionDurationScale, including zero.
enum class TranslationPresentationPhase { Idle, Requesting, Available, RecoverableFailure }

@Composable
fun TranslationReveal(phase: TranslationPresentationPhase, content: @Composable () -> Unit) {
    val distance = with(LocalDensity.current) { InterfaceMotion.TRAVEL_DP.dp.roundToPx() }
    val visibility = remember { MutableTransitionState(false) }
    visibility.targetState = phase == TranslationPresentationPhase.Available
    AnimatedVisibility(visibleState = visibility,
        enter = fadeIn(tween(InterfaceMotion.REVEAL)) + slideInVertically(tween(InterfaceMotion.REVEAL)) { if (android.animation.ValueAnimator.areAnimatorsEnabled()) distance else 0 }, exit = fadeOut(tween(InterfaceMotion.QUICK))) { content() }
}
