package com.hadithly.app.features.settings

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.preferences.*
import com.hadithly.app.core.theme.ArabicTypefaces
import com.hadithly.app.core.theme.LocalHadithlyColors

@Composable
internal fun ReaderPreferenceContent(
    preferences: ReaderPreferences,
    prefix: String,
    onLanguage: (String) -> Unit,
    onArabicFontSize: (Float) -> Unit,
    onTranslationFontSize: (Float) -> Unit,
    onTheme: (ReaderTheme) -> Unit,
    onArabicFont: (ArabicFont) -> Unit,
    onVisibility: (Boolean?, Boolean?) -> Unit,
    onDismiss: (() -> Unit)? = null,
    extraContent: @Composable () -> Unit = {},
) {
    val colors = LocalHadithlyColors.current
    var panel by remember { mutableStateOf<String?>(null) }
    BackHandler(enabled = panel != null) { panel = null }
    val scrollState = key(panel) { rememberScrollState() }
    Column(Modifier.testTag("$prefix.settings.sheet").fillMaxWidth()) {
        if (onDismiss != null || panel != null) {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
                if (panel != null) {
                    IconButton(onClick = { panel = null }, modifier = Modifier.testTag("$prefix.settings.back")) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = nativeText("Back"), tint = colors.textPrimary)
                    }
                }
                Text(nativeText(panel ?: "Settings"), style = MaterialTheme.typography.titleLarge, color = colors.textPrimary, modifier = Modifier.weight(1f).testTag("$prefix.settings.title"))
                if (onDismiss != null) {
                    TextButton(onClick = onDismiss, modifier = Modifier.testTag("$prefix.settings.close")) { Text(nativeText("Done"), color = colors.textPrimary) }
                }
            }
        }
        Column(Modifier.weight(1f, fill = false).verticalScroll(scrollState).padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
        when (panel) {
            null -> {
                PreferenceSection("Reader settings") {
                    PreferenceLink("Arabic type", "${readerFontLabel(preferences.arabicFont)} · ${preferences.arabicFontSize.toInt()} pt", "$prefix.settings.arabic") { panel = "Arabic type" }
                    PreferenceLink("Translation", "${preferences.translationLocale.uppercase()} · ${preferences.translationFontSize.toInt()} pt", "$prefix.settings.translation") { panel = "Translation" }
                    val theme = if (preferences.usesSeparateReaderTheme) preferences.readerTheme else preferences.appTheme
                    PreferenceLink("Appearance", theme.wire.replaceFirstChar { it.uppercase() }, "$prefix.settings.appearance") { panel = "Appearance" }
                }
                PreferenceSection("Show on page") {
                    PreferenceSwitch("Arabic", preferences.arabicVisible, "$prefix.visibility.arabic") { onVisibility(it, null) }
                    PreferenceSwitch("Translation", preferences.translationVisible, "$prefix.visibility.translation") { onVisibility(null, it) }
                }
                Text(nativeText("At least one text layer stays visible."), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, modifier = Modifier.padding(top = 6.dp, start = 16.dp))
                extraContent()
            }
            "Appearance" -> PreferenceSection("Reader appearance") {
                ReaderTheme.entries.forEach { theme ->
                    PreferenceChoice(theme.wire.replaceFirstChar { it.uppercase() }, (if (preferences.usesSeparateReaderTheme) preferences.readerTheme else preferences.appTheme) == theme, "$prefix.theme.${theme.wire}") { onTheme(theme) }
                }
            }
            "Arabic type" -> {
                PreferenceSection("Preview") {
                    Text("إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ", fontSize = preferences.arabicFontSize.sp, fontFamily = ArabicTypefaces.forFont(preferences.arabicFont), lineHeight = (preferences.arabicFontSize * 1.75).sp, textAlign = TextAlign.Center, color = colors.textPrimary, modifier = Modifier.fillMaxWidth().padding(16.dp).testTag("$prefix.typePreview"))
                    PreferenceSize(preferences.arabicFontSize, preferences.arabicFontSize > 18f, preferences.arabicFontSize < 40f, "$prefix.arabicSize", { onArabicFontSize(ArabicTypeSize.stepDown(preferences.arabicFontSize)) }, { onArabicFontSize(ArabicTypeSize.stepUp(preferences.arabicFontSize)) })
                }
                PreferenceSection("Arabic font") {
                    ArabicFont.entries.forEach { font -> PreferenceChoice(readerFontLabel(font), preferences.arabicFont == font, "$prefix.font.${font.wire}") { onArabicFont(font) } }
                }
            }
            "Translation" -> {
                PreferenceSection("Preview") {
                    Text(nativeText("Actions are judged by intentions."), fontSize = preferences.translationFontSize.sp, color = colors.textPrimary, modifier = Modifier.padding(16.dp))
                    PreferenceSize(preferences.translationFontSize, preferences.translationFontSize > 14f, preferences.translationFontSize < 22f, "$prefix.translationSize", { onTranslationFontSize(preferences.translationFontSize - 2f) }, { onTranslationFontSize(preferences.translationFontSize + 2f) })
                }
                PreferenceSection("Language") {
                    SupportedLanguages.all.forEach { (code, name) -> PreferenceChoice(name, preferences.translationLocale == code, "$prefix.language.$code") { onLanguage(code) } }
                }
                Text(nativeText("AI translations are labeled and grounded in cited sources."), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary, modifier = Modifier.padding(top = 6.dp, start = 16.dp))
            }
        }
        }
    }
}

@Composable
internal fun PreferenceSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    val colors = LocalHadithlyColors.current
    Text(nativeText(title), style = MaterialTheme.typography.labelMedium, color = colors.textSecondary, modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 8.dp))
    Surface(color = colors.surface, shape = RoundedCornerShape(12.dp)) { Column(content = content) }
}

@Composable
internal fun PreferenceSwitch(title: String, checked: Boolean, tag: String, onChange: (Boolean) -> Unit) {
    val colors = LocalHadithlyColors.current
    ListItem(
        headlineContent = { Text(nativeText(title), color = colors.textPrimary) },
        trailingContent = { Switch(checked = checked, onCheckedChange = null, colors = SwitchDefaults.colors(checkedTrackColor = colors.interactive, checkedThumbColor = colors.onInteractive)) },
        colors = ListItemDefaults.colors(containerColor = colors.surface),
        modifier = Modifier.toggleable(checked, role = Role.Switch, onValueChange = onChange).testTag(tag),
    )
}

@Composable
private fun PreferenceLink(title: String, value: String, tag: String, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Surface(onClick = onClick, color = colors.surface, modifier = Modifier.testTag(tag)) {
        ListItem(headlineContent = { Text(nativeText(title), color = colors.textPrimary) }, supportingContent = { Text(value, color = colors.textSecondary) }, trailingContent = { Icon(Icons.AutoMirrored.Filled.NavigateNext, null, tint = colors.textSecondary) }, colors = ListItemDefaults.colors(containerColor = colors.surface))
    }
}

@Composable
private fun PreferenceChoice(title: String, selected: Boolean, tag: String, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    ListItem(headlineContent = { Text(nativeText(title), color = colors.textPrimary) }, trailingContent = { RadioButton(selected, onClick = null, colors = RadioButtonDefaults.colors(selectedColor = colors.interactive, unselectedColor = colors.textSecondary)) }, colors = ListItemDefaults.colors(containerColor = colors.surface), modifier = Modifier.selectable(selected, role = Role.RadioButton, onClick = onClick).testTag(tag))
}

@Composable
private fun PreferenceSize(value: Float, canDecrease: Boolean, canIncrease: Boolean, tag: String, decrease: () -> Unit, increase: () -> Unit) {
    val colors = LocalHadithlyColors.current
    ListItem(headlineContent = { Text(nativeText("Text size"), color = colors.textPrimary) }, supportingContent = { Text(nativeText("%1\$s pt", value.toInt()), color = colors.textSecondary) }, trailingContent = {
        Row {
            IconButton(onClick = decrease, enabled = canDecrease, modifier = Modifier.testTag("$tag.smaller")) { Icon(Icons.Filled.Remove, nativeText("Smaller type"), tint = if (canDecrease) colors.textPrimary else colors.textSecondary) }
            IconButton(onClick = increase, enabled = canIncrease, modifier = Modifier.testTag("$tag.larger")) { Icon(Icons.Filled.Add, nativeText("Larger type"), tint = if (canIncrease) colors.textPrimary else colors.textSecondary) }
        }
    }, colors = ListItemDefaults.colors(containerColor = colors.surface))
}

private fun readerFontLabel(font: ArabicFont): String = when (font) {
    ArabicFont.SYSTEM -> "System"
    ArabicFont.AMIRI -> "Amiri"
    ArabicFont.SCHEHERAZADE_NEW -> "Scheherazade New"
    ArabicFont.NOTO_NASKH_ARABIC -> "Noto Naskh Arabic"
}
