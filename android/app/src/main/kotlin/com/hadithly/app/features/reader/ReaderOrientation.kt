package com.hadithly.app.features.reader

import android.app.Activity
import android.content.pm.ActivityInfo
import android.hardware.display.DisplayManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.accessibility.AccessibilityManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import kotlinx.coroutines.delay

internal class ReaderOrientation(private val activity: Activity) {
    private var previousOrientation by mutableStateOf<Int?>(null)
    val isLocked: Boolean get() = previousOrientation != null
    var showCorner by mutableStateOf(false)

    fun toggle() {
        if (isLocked) {
            restore()
        } else {
            previousOrientation = activity.requestedOrientation
            activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LOCKED
        }
    }

    fun restore() {
        previousOrientation?.let { activity.requestedOrientation = it }
        previousOrientation = null
    }
}

@Composable
internal fun rememberReaderOrientation(activity: Activity, view: View, readerId: Long): ReaderOrientation {
    val orientation = remember(activity, readerId) { ReaderOrientation(activity) }
    var rotationChanges by remember(orientation) { mutableIntStateOf(0) }
    DisposableEffect(orientation, view) {
        val displayManager = activity.getSystemService(DisplayManager::class.java)
        var previousRotation = view.display?.rotation
        val listener = object : DisplayManager.DisplayListener {
            override fun onDisplayAdded(displayId: Int) = Unit
            override fun onDisplayRemoved(displayId: Int) = Unit
            override fun onDisplayChanged(displayId: Int) {
                val display = view.display?.takeIf { it.displayId == displayId } ?: return
                val rotation = display.rotation
                if (previousRotation != null && previousRotation != rotation) rotationChanges++
                previousRotation = rotation
            }
        }
        displayManager.registerDisplayListener(listener, Handler(Looper.getMainLooper()))
        onDispose {
            displayManager.unregisterDisplayListener(listener)
            orientation.restore()
        }
    }
    LaunchedEffect(orientation, rotationChanges) {
        if (rotationChanges > 0) {
            orientation.showCorner = true
            val timeout = if (Build.VERSION.SDK_INT >= 29) {
                activity.getSystemService(AccessibilityManager::class.java)
                    .getRecommendedTimeoutMillis(3_000, AccessibilityManager.FLAG_CONTENT_CONTROLS)
            } else 3_000
            delay(timeout.toLong())
            orientation.showCorner = false
        }
    }
    return orientation
}
