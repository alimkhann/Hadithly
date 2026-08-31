package com.hadithly.app.features.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Person
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.rememberApp
import com.clerk.api.Clerk
import kotlinx.coroutines.launch

/**
 * Settings for this phase: account (sign in / out), reading language, and
 * Arabic type size with a live preview. The daily-hadith notification
 * section and Saved/Today tabs arrive with the next Android increment.
 */
@Composable
fun SettingsScreen(onShowSignIn: () -> Unit) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val language by app.settings.preferredLanguage.collectAsStateWithLifecycle()
    val arabicFontSize by app.settings.arabicFontSize.collectAsStateWithLifecycle()
    val syncSummary by app.session.syncSummary.collectAsStateWithLifecycle()
    val signedIn = app.isSignedIn()
    val user = if (signedIn) Clerk.user else null

    Column(
        verticalArrangement = Arrangement.spacedBy(16.dp),
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
    ) {
        Text(
            text = "Settings",
            fontSize = 30.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
            modifier = Modifier.padding(top = 20.dp),
        )

        // Account
        Column(
            verticalArrangement = Arrangement.spacedBy(12.dp),
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.surface, RoundedCornerShape(14.dp))
                .padding(16.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Box(
                    modifier = Modifier
                        .size(38.dp)
                        .background(colors.surfaceElevated, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Filled.Person,
                        contentDescription = null,
                        tint = colors.textSecondary,
                        modifier = Modifier.size(20.dp),
                    )
                }
                Column {
                    Text(
                        text = if (signedIn) (user?.firstName ?: "Signed in") else "Guest",
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                        color = colors.textPrimary,
                    )
                    Text(
                        text = if (signedIn) "Your reading syncs across devices." else "Reading works without an account.",
                        fontSize = 12.sp,
                        color = colors.textSecondary,
                    )
                }
            }

            if (signedIn) {
                TextButton(onClick = { app.appScope.launch { Clerk.auth.signOut() } }) {
                    Text("Sign out", color = colors.destructive)
                }
            } else {
                Button(
                    onClick = onShowSignIn,
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.accent,
                        contentColor = Color.Black,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text("Sign in", fontWeight = FontWeight.Bold)
                }
            }

            syncSummary?.let {
                Text(text = it, fontSize = 12.sp, color = colors.textSecondary)
            }
        }

        // Translation language
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.surface, RoundedCornerShape(14.dp))
                .padding(16.dp),
        ) {
            Text("Translation language", fontSize = 13.sp, color = colors.textSecondary)
            for ((code, name) in SupportedLanguages.all) {
                val selected = code == language
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            if (selected) colors.accentSoft else colors.surfaceElevated,
                            RoundedCornerShape(12.dp),
                        )
                        .clickable { app.settings.setPreferredLanguage(code) }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                ) {
                    Text(name, fontSize = 15.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    if (selected) {
                        Icon(
                            Icons.Filled.CheckCircle,
                            contentDescription = null,
                            tint = colors.accent,
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
        }

        // Arabic type size
        Column(
            verticalArrangement = Arrangement.spacedBy(8.dp),
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.surface, RoundedCornerShape(14.dp))
                .padding(16.dp),
        ) {
            Text("Arabic type size", fontSize = 13.sp, color = colors.textSecondary)
            Text(
                text = "بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ",
                fontSize = arabicFontSize.sp,
                color = colors.textPrimary,
            )
            Slider(
                value = arabicFontSize,
                onValueChange = { app.settings.setArabicFontSize(it) },
                valueRange = 18f..40f,
                colors = SliderDefaults.colors(
                    thumbColor = colors.accent,
                    activeTrackColor = colors.accent,
                    inactiveTrackColor = colors.surfaceElevated,
                ),
            )
        }

        Spacer(modifier = Modifier.height(24.dp))
    }
}
