package com.hadithly.app.features.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/** Wordless, code-native collection cover shared by Home and Library. */
@androidx.compose.runtime.Composable
fun CollectionCover(position: Int, modifier: Modifier = Modifier) {
    val paper = collectionPaper(position)
    val ink = collectionInk(position)
    val shape = RoundedCornerShape(5.dp)
    Box(
        modifier = modifier
            .shadow(10.dp, shape, ambientColor = Color.Black.copy(alpha = 0.32f), spotColor = Color.Black.copy(alpha = 0.46f))
            .clip(shape)
            .background(Brush.linearGradient(listOf(paper, paper.copy(alpha = 0.72f), ink.copy(alpha = 0.52f))))
            .padding(7.dp),
    ) {
        Box(Modifier.fillMaxSize().clip(RoundedCornerShape(2.dp)).background(Color.White.copy(alpha = 0.08f)))
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxSize()
                .width(6.dp)
                .background(Brush.horizontalGradient(listOf(ink.copy(alpha = 0.8f), ink.copy(alpha = 0.18f))), RoundedCornerShape(topStart = 5.dp, bottomStart = 5.dp)),
        )
    }
}

private fun collectionPaper(position: Int) = listOf(
    Color(0xFFC8A46D), Color(0xFFA96F61), Color(0xFF8B9B86), Color(0xFFB48F77),
    Color(0xFF8F93A5), Color(0xFF9A8065), Color(0xFF78949A),
).getOrElse(position - 1) { Color(0xFF2A2A2C) }

private fun collectionInk(position: Int) = listOf(
    Color(0xFF4B3423), Color(0xFF4C2728), Color(0xFF29433A), Color(0xFF513A30),
    Color(0xFF323948), Color(0xFF4C392B), Color(0xFF29464B),
).getOrElse(position - 1) { Color(0xFF1A1A1A) }
