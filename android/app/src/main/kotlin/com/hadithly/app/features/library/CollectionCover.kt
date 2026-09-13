package com.hadithly.app.features.library

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.Image
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import com.hadithly.app.R

/** Wordless, code-native collection cover shared by Home and Library. */
@androidx.compose.runtime.Composable
fun CollectionCover(position: Int, modifier: Modifier = Modifier) {
    val shape = RoundedCornerShape(5.dp)
    Box(
        modifier = modifier
            .shadow(10.dp, shape, ambientColor = Color.Black.copy(alpha = 0.32f), spotColor = Color.Black.copy(alpha = 0.46f))
            .clip(shape)
            .background(Color(0xFF1A1A1A)),
    ) {
        Image(
            painter = painterResource(collectionCoverResource(position)),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxSize()
                .width(6.dp)
                .background(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = 0.34f), Color.Transparent)), RoundedCornerShape(topStart = 5.dp, bottomStart = 5.dp)),
        )
        Box(Modifier.fillMaxSize().padding(1.dp).clip(shape).background(Color.Transparent))
    }
}

private fun collectionCoverResource(position: Int) = when (position) {
    1 -> R.drawable.cover_bukhari
    2 -> R.drawable.cover_muslim
    3 -> R.drawable.cover_sunan_nasai
    4 -> R.drawable.cover_abu_dawood
    5 -> R.drawable.cover_tirmidhi
    6 -> R.drawable.cover_ibn_majah
    else -> R.drawable.cover_mishkat
}
