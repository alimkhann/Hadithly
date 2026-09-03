package com.hadithly.app.features.onboarding

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
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.core.theme.Spacing

/** Onboarding is intentionally short: value → language → straight in. Account creation is deferred (guest mode first). */
@Composable
fun OnboardingFlow(
    selectedLanguage: String,
    onSelectLanguage: (String) -> Unit,
    onComplete: () -> Unit,
) {
    var step by remember { mutableIntStateOf(0) }

    when (step) {
        0 -> WelcomeScreen(onContinue = { step = 1 })
        else -> LanguagePickerScreen(
            selection = selectedLanguage,
            onSelect = onSelectLanguage,
            onContinue = onComplete,
        )
    }
}

@Composable
fun WelcomeScreen(onContinue: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .padding(24.dp),
    ) {
        Column(
            modifier = Modifier.align(Alignment.Center),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(Spacing.lg),
        ) {
            Icon(
                imageVector = Icons.Filled.MenuBook,
                contentDescription = null,
                tint = colors.accent,
                modifier = Modifier.size(56.dp),
            )
            Text(
                text = "Hadithly",
                fontSize = 34.sp,
                fontWeight = FontWeight.Bold,
                color = colors.textPrimary,
            )
            Text(
                text = "Read the hadith collections in your language — clean, calm, and true to the sources.",
                fontSize = 16.sp,
                color = colors.textSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 8.dp),
            )
        }

        Column(
            modifier = Modifier.align(Alignment.BottomCenter),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            AccentButton(text = "Continue", onClick = onContinue)
            Text(
                text = "You can create an account later — everything you need to start reading works without one.",
                fontSize = 13.sp,
                color = colors.textSecondary,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 16.dp),
            )
        }
    }
}

@Composable
fun LanguagePickerScreen(
    selection: String,
    onSelect: (String) -> Unit,
    onContinue: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background)
            .padding(24.dp),
    ) {
        Text(
            text = "Choose your reading language",
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold,
            color = colors.textPrimary,
            modifier = Modifier.padding(top = Spacing.lg),
        )
        Text(
            text = "You can change this any time in Settings.",
            fontSize = 15.sp,
            color = colors.textSecondary,
            modifier = Modifier.padding(top = Spacing.xs),
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        LazyColumn(
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            modifier = Modifier.weight(1f),
        ) {
            items(SupportedLanguages.all, key = { it.first }) { (code, name) ->
                LanguageRow(
                    name = name,
                    selected = selection == code,
                    onClick = { onSelect(code) },
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.md))
        AccentButton(text = "Continue", onClick = onContinue)
    }
}

@Composable
private fun LanguageRow(name: String, selected: Boolean, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .fillMaxWidth()
            .background(
                if (selected) colors.accentSoft else colors.surface,
                RoundedCornerShape(12.dp),
            )
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        Text(
            text = name,
            fontSize = 16.sp,
            color = colors.textPrimary,
            modifier = Modifier.weight(1f),
        )
        if (selected) {
            Icon(
                imageVector = Icons.Filled.Check,
                contentDescription = "Selected",
                tint = colors.accent,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
fun AccentButton(text: String, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Button(
        onClick = onClick,
        shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = colors.accent,
            contentColor = Color.Black,
        ),
        modifier = Modifier
            .fillMaxWidth()
            .height(52.dp),
    ) {
        Text(text = text, fontWeight = FontWeight.Bold, fontSize = 16.sp)
    }
}
