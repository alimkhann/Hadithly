package com.hadithly.app.core.theme

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

data class QuietDestination(val title: String, val icon: ImageVector, val selectedIcon: ImageVector = icon, val tag: String)

/** Material owns selection, ripple, focus and semantics; the surface stays quiet. */
@Composable
fun QuietNavigationBar(destinations: List<QuietDestination>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    val largeText = LocalDensity.current.fontScale > 1.5f
    Surface(modifier, shape = RoundedCornerShape(28.dp), color = colors.surface.copy(alpha = .97f),
        border = BorderStroke(.5.dp, colors.divider.copy(alpha = .55f))) {
        Column {
            destinations.withIndex().toList().chunked(if (largeText) 2 else destinations.size).forEach { row ->
                ShortNavigationBar(containerColor = Color.Transparent, contentColor = colors.textPrimary,
                    windowInsets = WindowInsets(0, 0, 0, 0)) {
                    row.forEach { (index, destination) ->
                        ShortNavigationBarItem(selected = selected == index, onClick = { onSelect(index) },
                            modifier = Modifier.testTag(destination.tag),
                            iconPosition = if (largeText) NavigationItemIconPosition.Start else NavigationItemIconPosition.Top,
                            icon = { Icon(if (selected == index) destination.selectedIcon else destination.icon, null, Modifier.size(22.dp)) },
                            label = { Text(destination.title, fontSize = 11.sp, maxLines = 2) },
                            colors = ShortNavigationBarItemDefaults.colors(
                                selectedIconColor = colors.textPrimary, selectedTextColor = colors.textPrimary,
                                selectedIndicatorColor = colors.interactiveSoft,
                                unselectedIconColor = colors.textSecondary, unselectedTextColor = colors.textSecondary))
                    }
                }
            }
        }
    }
}
