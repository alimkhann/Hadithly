package com.hadithly.app.features.reader

import android.view.HapticFeedbackConstants
import android.view.View

/**
 * R6 reader fix round: restrained, native haptics. Every trigger point in
 * the reader routes through [ReaderHaptics.perform] so unit tests can pin
 * the mapping without a View.
 */
enum class ReaderHapticKind {
    /** Reader menu opened or closed. */
    MENU_OPEN_CLOSE,
    /** A reader menu card tapped. */
    MENU_ITEM,
    /** The tap that toggles focused/unfocused chrome (the only chrome-toggle feedback). */
    TAP_TOGGLE,
    /** Long-press opened the per-hadith context menu. */
    LONG_PRESS_MENU,
    /** A bookmark or favorite was added (never on remove). */
    BOOKMARK_FAVORITE_ADD,
    /** The user tried to hide BOTH text layers (rejected). */
    REJECT_BOTH_HIDDEN,
}

object ReaderHaptics {
    /** The native [HapticFeedbackConstants] value for each trigger. */
    fun constantFor(kind: ReaderHapticKind): Int = when (kind) {
        ReaderHapticKind.MENU_OPEN_CLOSE -> HapticFeedbackConstants.CLOCK_TICK
        ReaderHapticKind.MENU_ITEM -> HapticFeedbackConstants.CONTEXT_CLICK
        ReaderHapticKind.TAP_TOGGLE -> HapticFeedbackConstants.KEYBOARD_TAP
        ReaderHapticKind.LONG_PRESS_MENU -> HapticFeedbackConstants.CONTEXT_CLICK
        ReaderHapticKind.BOOKMARK_FAVORITE_ADD -> HapticFeedbackConstants.CONFIRM
        ReaderHapticKind.REJECT_BOTH_HIDDEN -> HapticFeedbackConstants.REJECT
    }

    /** Performs the mapped constant on [view]; returns the platform result. */
    fun perform(view: View, kind: ReaderHapticKind): Boolean =
        view.performHapticFeedback(constantFor(kind))
}
