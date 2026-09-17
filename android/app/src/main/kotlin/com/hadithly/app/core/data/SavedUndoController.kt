package com.hadithly.app.core.data

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

const val UNDO_NOTICE_MILLIS = 5_000L

class SavedUndoNotice(val message: String, val deadlineElapsedMillis: Long) {
    fun remainingFraction(nowElapsedMillis: Long): Float =
        ((deadlineElapsedMillis - nowElapsedMillis) / UNDO_NOTICE_MILLIS.toFloat()).coerceIn(0f, 1f)
}

class SavedUndoController(
    private val scope: CoroutineScope,
    val now: () -> Long,
) {
    private val _notice = MutableStateFlow<SavedUndoNotice?>(null)
    val notice: StateFlow<SavedUndoNotice?> = _notice
    private var action: (() -> Unit)? = null
    private var expiry: Job? = null

    fun show(message: String, undo: () -> Unit) {
        clear()
        val notice = SavedUndoNotice(message, now() + UNDO_NOTICE_MILLIS)
        action = undo
        _notice.value = notice
        expiry = scope.launch {
            delay((notice.deadlineElapsedMillis - now()).coerceAtLeast(0))
            _notice.value = null
            action = null
        }
    }

    fun remainingFraction(notice: SavedUndoNotice): Float = notice.remainingFraction(now())

    fun undo() {
        val undo = action.takeIf { _notice.value?.remainingFraction(now())?.let { it > 0f } == true }
        clear()
        undo?.invoke()
    }

    fun clear() {
        expiry?.cancel()
        expiry = null
        action = null
        _notice.value = null
    }
}
