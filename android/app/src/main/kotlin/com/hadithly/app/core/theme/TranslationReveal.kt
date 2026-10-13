package com.hadithly.app.core.theme

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.MutableTransitionState
import androidx.compose.runtime.remember
import androidx.compose.runtime.Composable

// AnimatedVisibility obeys the platform MotionDurationScale, including zero.
enum class TranslationPresentationPhase { Idle, Requesting, Available, RecoverableFailure }

@Composable
fun TranslationReveal(phase: TranslationPresentationPhase, content: @Composable () -> Unit) {
    val visibility = remember { MutableTransitionState(false) }
    visibility.targetState = phase == TranslationPresentationPhase.Available
    AnimatedVisibility(visibleState = visibility,
        enter = fadeIn(tween(300)), exit = fadeOut(tween(300))) { content() }
}
