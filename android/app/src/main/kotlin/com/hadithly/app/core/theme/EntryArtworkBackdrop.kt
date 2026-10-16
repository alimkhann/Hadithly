package com.hadithly.app.core.theme

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import com.hadithly.app.R

@Composable
fun EntryArtworkBackdrop(dimmed: Boolean = false) {
    val colors = LocalHadithlyColors.current
    val quiet = dimmed || LocalDensity.current.fontScale > 1.5f
    Box(Modifier.fillMaxSize()) {
        Image(painterResource(if (colors.background == ReaderPalettes.dark.background) R.drawable.onboarding_book else R.drawable.onboarding_book_light), contentDescription = null,
            contentScale = ContentScale.Crop, modifier = Modifier.matchParentSize())
        if (quiet) Box(Modifier.matchParentSize().background(colors.background.copy(alpha = .9f)))
        Box(Modifier.matchParentSize().background(Brush.verticalGradient(
            0f to colors.background.copy(alpha = .96f),
            .38f to colors.background.copy(alpha = .84f),
            .62f to colors.background.copy(alpha = .06f),
            1f to colors.background.copy(alpha = .96f))))
    }
}
