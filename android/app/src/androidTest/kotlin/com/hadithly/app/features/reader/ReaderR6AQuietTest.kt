package com.hadithly.app.features.reader

import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.UriHandler
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import com.hadithly.app.core.data.AuthenticityClaim
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.preferences.PageDirection
import com.hadithly.app.core.preferences.ReaderPagingPolicy
import com.hadithly.app.core.preferences.ReaderPageTurn
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * R6A slice A on the hadithly emulator: the Sajda-quiet page. No dividers,
 * no overflow button, dim provider-number markers, grade dot plus compact
 * label, source sheet, volume corner/header, and the adjacent chevron
 * cluster — with the long-press menu and TalkBack actions intact.
 */
class ReaderR6AQuietTest {
    @get:Rule
    val compose = createComposeRule()

    private fun hadith(
        providerHadithId: String = "57",
        authenticity: AuthenticityClaim = AuthenticityClaim(
            kind = "source",
            normalizedGrade = "sahih",
            claimScope = "hadith",
            sourceLabel = "Sunnah.now",
            sourceName = "Sunnah.now",
            sourceUrl = "https://sunnah.now/bukhari:57",
            verificationMethod = "provider",
        ),
    ) = ReaderHadith(
        _id = "h-$providerHadithId",
        provider = "sunnah_now",
        canonicalId = "sunnah_now:bukhari:$providerHadithId",
        providerHadithId = providerHadithId,
        collectionSlug = "bukhari",
        arabicText = "حَدَّثَنَا",
        englishText = "He said:",
        narrator = "Narrated Abu Huraira:",
        narratorAr = "رواه أبو هريرة:",
        referenceDisplay = "Sahih al-Bukhari · Hadith $providerHadithId",
        collectionName = "Sahih al-Bukhari",
        chapterName = "Belief",
        authenticity = authenticity,
    )

    private class FakeDeps(
        override val isBookmarked: Boolean = false,
        override val isFavorite: Boolean = false,
    ) : HadithBlockDeps {
        var bookmarks = 0
        var favorites = 0
        override val hasNote = false
        override fun onToggleBookmark() {
            bookmarks += 1
        }
        override fun onToggleFavorite() {
            favorites += 1
        }
    }

    @Composable
    private fun block(
        hadith: ReaderHadith = hadith(),
        deps: HadithBlockDeps = FakeDeps(),
        translationState: TranslationUiState? = null,
        preferences: ReaderPreferences = ReaderPreferences(),
        onShowSource: () -> Unit = {},
    ) {
        HadithlyTheme {
            HadithBlock(
                hadith = hadith,
                translationState = translationState,
                language = "en",
                arabicFontSize = 26f,
                preferences = preferences,
                deps = deps,
                onTap = {},
                onRetry = {},
                onShowSource = onShowSource,
                onEditNote = {},
                onSuggest = {},
                onReport = {},
                onShowPaywall = {},
            )
        }
    }

    @Test fun translationSourcesShareTheHadithHeaderSheet() {
        val translation = com.hadithly.app.core.data.ReaderTranslation("prepared-sources", "Prepared sourced translation", source = "gemini_ai", sourceLabel = "AI translation", citations = listOf(com.hadithly.app.core.data.ReaderCitation("https://example.org/reference", "Prepared reference", "example.org")))
        val open = androidx.compose.runtime.mutableStateOf(false)
        compose.setContent {
            HadithlyTheme {
                if (open.value) HadithSourceSheet(hadith(), translation)
                else block(translationState = TranslationUiState.Loaded(translation), onShowSource = { open.value = true })
            }
        }
        compose.onNodeWithText("Prepared sourced translation").assertIsDisplayed()
        compose.onNodeWithText("AI").assertDoesNotExist()
        compose.onNodeWithTag("reader.hadithLabel").performClick()
        compose.onNodeWithTag("reader.sourceSheet").assertIsDisplayed()
        compose.onNodeWithText("Prepared reference").assertIsDisplayed()
        compose.onNodeWithText("Prepared reference").assertHasClickAction()
        compose.onNodeWithTag("translation.sources.ai").assertIsDisplayed()
        val context = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext
        java.io.File(context.cacheDir, "a3-reader-sources.png").outputStream().use {
            compose.onNodeWithTag("reader.sourceSheet").captureToImage().asAndroidBitmap().compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it)
        }
    }

    @Test fun translationWithoutCitationsDoesNotClaimExternalGrounding() {
        val translation = com.hadithly.app.core.data.ReaderTranslation("uncited", "Prepared uncited translation", source = "gemini_ai", sourceLabel = "AI translation", aiModel = "Prepared model", sourceReferenceUrl = "https://example.org/original")
        var opened: String? = null
        var noSources = ""
        var reference = ""
        val handler = object : UriHandler { override fun openUri(uri: String) { opened = uri } }
        compose.setContent {
            noSources = com.hadithly.app.core.preferences.nativeText("No external sources were cited for this translation.")
            reference = com.hadithly.app.core.preferences.nativeText("Reference: %1\$s", "https://example.org/original")
            CompositionLocalProvider(LocalUriHandler provides handler) { HadithlyTheme { TranslationSourceDetails(translation) } }
        }
        compose.onNodeWithText(noSources).assertIsDisplayed()
        compose.onNodeWithText(reference).assertHasClickAction()
        compose.onNodeWithText("grounded in cited sources", substring = true).assertDoesNotExist()
        compose.onNodeWithTag("translation.sources.ai").assertIsDisplayed()
        compose.onNodeWithText(reference).performClick()
        assertEquals("https://example.org/original", opened)
    }

    @Test
    fun quietBlockHasNoOverflowOrLegacyLines() {
        compose.setContent { block() }

        compose.onNodeWithTag("reader.moreActions").assertDoesNotExist()
        compose.onNodeWithTag("reader.reference").assertDoesNotExist()
        compose.onNodeWithTag("reader.authenticity").assertDoesNotExist()
        compose.onNodeWithText("Hadith 57", substring = true).assertDoesNotExist()
        // The dim bare-number marker and the bottom compact label are gone:
        // one top header per hadith, no duplication.
        compose.onNodeWithTag("reader.hadithMarker").assertDoesNotExist()
    }

    @Test
    fun headerShowsBracketedLabelAtTop() {
        compose.setContent { block() }

        compose.onNodeWithTag("reader.hadithLabel").assertIsDisplayed()
        compose.onNodeWithText("Bukhari – 57").assertIsDisplayed()
    }

    @Test
    fun headerTapOpensSource() {
        var opened = 0
        compose.setContent { block(onShowSource = { opened += 1 }) }

        // One header per hadith: no bare-number marker, no grade-dot marker
        // tag — the dot is an untagged part of the header tap target.
        compose.onNodeWithTag("reader.gradeDot", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag("reader.hadithMarker", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag("reader.hadithLabel").assertIsDisplayed()
        compose.onNodeWithText("Bukhari – 57").assertIsDisplayed()
        compose.onNodeWithTag("reader.hadithLabel").performClick()
        compose.runOnIdle { assertEquals(1, opened) }
    }

    @Test
    fun narratorShowsAtLeadingEdgeWhenTranslationVisible() {
        compose.setContent { block() }

        // Plain-text children merge into the block's clickable node, so
        // assert them in the unmerged tree.
        compose.onNodeWithTag("reader.narrator", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("Narrated Abu Huraira:").assertIsDisplayed()
    }

    @Test
    fun narratorShowsAboveArabicWhenTranslationLayerHidden() {
        compose.setContent {
            block(preferences = ReaderPreferences(translationVisible = false))
        }

        // Arabic-only mode shows the provider's Arabic narrator line.
        compose.onNodeWithTag("reader.narrator", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithText("رواه أبو هريرة:").assertIsDisplayed()
        compose.onNodeWithText("Narrated Abu Huraira:").assertDoesNotExist()
        compose.onNodeWithTag("reader.arabic", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun arabicOnlyNarratorHidesWhenAbsent() {
        compose.setContent {
            block(
                hadith = hadith().copy(narratorAr = null),
                preferences = ReaderPreferences(translationVisible = false),
            )
        }

        // Missing narratorAr stays hidden in Arabic-only mode.
        compose.onNodeWithTag("reader.narrator", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag("reader.arabic", useUnmergedTree = true).assertIsDisplayed()
    }

    @Test
    fun savedBookmarkMiniMarkAppearsWhenBookmarked() {
        compose.setContent { block(deps = FakeDeps(isBookmarked = true)) }

        compose.onNodeWithTag("reader.savedBookmark", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithTag("reader.savedFavorite", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test
    fun savedFavoriteMiniMarkAppearsWhenFavorited() {
        compose.setContent { block(deps = FakeDeps(isFavorite = true)) }

        compose.onNodeWithTag("reader.savedFavorite", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithTag("reader.savedBookmark", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test
    fun noMiniMarksOrNoteIconWhenUnsaved() {
        compose.setContent { block() }

        compose.onNodeWithTag("reader.savedBookmark", useUnmergedTree = true).assertDoesNotExist()
        compose.onNodeWithTag("reader.savedFavorite", useUnmergedTree = true).assertDoesNotExist()
    }

    @Test
    fun sourceSheetShowsNameScopeAndUrl() {
        compose.setContent {
            HadithlyTheme { HadithSourceSheet(hadith = hadith()) }
        }

        compose.onNodeWithTag("reader.sourceSheet").assertIsDisplayed()
        compose.onNodeWithText("Sunnah.now").assertIsDisplayed()
        compose.onNodeWithText("Sahih hadith · Sunnah.now").assertIsDisplayed()
        compose.onNodeWithText("https://sunnah.now/bukhari:57").assertIsDisplayed()
    }

    @Test
    fun sourceSheetOmitsMissingUrl() {
        val noUrl = hadith().copy(
            authenticity = hadith().authenticity.copy(sourceUrl = ""),
        )
        compose.setContent {
            HadithlyTheme { HadithSourceSheet(hadith = noUrl) }
        }

        compose.onNodeWithTag("reader.sourceSheet").assertIsDisplayed()
        compose.onNodeWithText("https://", substring = true).assertDoesNotExist()
    }

    @Test
    fun volumeCornerShowsTitleOnly() {
        compose.setContent {
            HadithlyTheme {
                VolumeCornerLabel(title = "Volume 2", range = null)
            }
        }
        compose.onNodeWithTag("reader.volumeCorner").assertIsDisplayed()
        compose.onNodeWithText("Volume 2").assertIsDisplayed()
    }

    @Test
    fun volumeCornerAppendsCachedRange() {
        compose.setContent {
            HadithlyTheme {
                VolumeCornerLabel(title = "Volume 2", range = 58 to 101)
            }
        }
        compose.onNodeWithText("Volume 2: 58–101").assertIsDisplayed()
    }

    @Test fun volumeCountsAndLanguageTotalsRenderInEveryLocale() {
        var locale by androidx.compose.runtime.mutableStateOf("en")
        compose.setContent {
            androidx.compose.runtime.key(locale) {
                val context = androidx.compose.ui.platform.LocalContext.current
                val config = android.content.res.Configuration(androidx.compose.ui.platform.LocalConfiguration.current).apply { setLocale(java.util.Locale.forLanguageTag(locale)) }
                val resources = context.createConfigurationContext(config).resources
                androidx.compose.runtime.CompositionLocalProvider(
                    androidx.compose.ui.platform.LocalConfiguration provides config,
                    androidx.compose.ui.platform.LocalResources provides resources,
                    androidx.compose.ui.platform.LocalLayoutDirection provides if (com.hadithly.app.core.preferences.LocaleFallback.isRTL(locale)) androidx.compose.ui.unit.LayoutDirection.Rtl else androidx.compose.ui.unit.LayoutDirection.Ltr,
                ) {
                    HadithlyTheme {
                        androidx.compose.foundation.layout.Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding().padding(16.dp)) {
                            VolumeStartHeader(title = "Prepared volume", hadithCount = 3)
                            androidx.compose.material3.Text(androidx.compose.ui.res.pluralStringResource(com.hadithly.app.R.plurals.settings_languages_available, 15, 15))
                        }
                    }
                }
            }
        }
        for ((tag, countTemplate, languagesTemplate) in listOf(
            Triple("en", "%d hadiths", "%d languages available"),
            Triple("ar", "%d أحاديث", "%d لغة متاحة"),
            Triple("ru", "%d хадиса", "%d языков доступно"),
            Triple("kk", "%d хадис", "%d тіл қолжетімді"),
            Triple("ky", "%d хадис", "%d тил жеткиликтүү"),
            Triple("uz", "%d hadis", "%d ta til mavjud"),
            Triple("tr", "%d hadis", "%d dil kullanılabilir"),
            Triple("id", "%d hadis", "%d bahasa tersedia"),
            Triple("ur", "%d احادیث", "%d زبانیں دستیاب ہیں"),
            Triple("fr", "%d hadiths", "%d langues disponibles"),
            Triple("es-419", "%d hadices", "%d idiomas disponibles"),
            Triple("pt-BR", "%d hadiths", "%d idiomas disponíveis"),
            Triple("sw", "%d hadithi", "%d lugha zinapatikana"),
            Triple("hi", "%d हदीस", "%d भाषाएँ उपलब्ध"),
            Triple("bn", "%d হাদিস", "%dটি ভাষা উপলব্ধ")
        )) {
            compose.runOnIdle { locale = tag }
            val value = java.util.Locale.forLanguageTag(tag)
            compose.onNodeWithText(String.format(value, countTemplate, 3)).assertIsDisplayed()
            compose.onNodeWithText(String.format(value, languagesTemplate, 15)).assertIsDisplayed()
            val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
            val instrumentation = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation()
            val output = java.io.File(instrumentation.targetContext.getExternalFilesDir(null), "plural-count-$tag.png")
            output.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            bitmap.recycle()
            android.os.ParcelFileDescriptor.AutoCloseInputStream(instrumentation.uiAutomation.executeShellCommand("cp ${output.absolutePath} /sdcard/Pictures/plural-count-$tag.png")).use { it.readBytes() }
        }
    }

    @Test fun countCategoriesPreserveArabicDualAndRussianEndings() {
        val context = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext
        val counts = listOf(0, 1, 2, 3, 11, 21, 100, 102)
        val expected = mapOf(
            "ar" to listOf(
                "لا أحاديث" to "لا توجد لغات متاحة", "%d حديث" to "%d لغة متاحة",
                "حديثان" to "لغتان متاحتان", "%d أحاديث" to "%d لغات متاحة",
                "%d حديثًا" to "%d لغة متاحة", "%d حديثًا" to "%d لغة متاحة",
                "%d حديث" to "%d لغة متاحة", "%d حديث" to "%d لغة متاحة",
            ),
            "ru" to listOf(
                "%d хадисов" to "%d языков доступно", "%d хадис" to "%d язык доступен",
                "%d хадиса" to "%d языка доступны", "%d хадиса" to "%d языка доступны",
                "%d хадисов" to "%d языков доступно", "%d хадис" to "%d язык доступен",
                "%d хадисов" to "%d языков доступно", "%d хадиса" to "%d языка доступны",
            ),
        )
        for ((tag, forms) in expected) {
            val locale = java.util.Locale.forLanguageTag(tag)
            val config = android.content.res.Configuration(context.resources.configuration).apply { setLocale(locale) }
            val resources = context.createConfigurationContext(config).resources
            for ((index, count) in counts.withIndex()) {
                assertEquals("$tag:$count", String.format(locale, forms[index].first, count), resources.getQuantityString(com.hadithly.app.R.plurals.reader_hadith_count, count, count))
                assertEquals("$tag:$count", String.format(locale, forms[index].second, count), resources.getQuantityString(com.hadithly.app.R.plurals.settings_languages_available, count, count))
            }
        }
    }

    @Test fun volumeCountUsesRussianPluralForms() {
        val context = androidx.test.platform.app.InstrumentationRegistry.getInstrumentation().targetContext
        val config = android.content.res.Configuration(context.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag("ru")) }
        val resources = context.createConfigurationContext(config).resources
        assertEquals("3 хадиса", resources.getQuantityString(com.hadithly.app.R.plurals.reader_hadith_count, 3, 3))
    }

    @Test
    fun volumeHeaderShowsLocalizedCount() {
        // Resolve the expectation through the framework ICU plural table in
        // the same configuration (the emulator may run a non-English system
        // locale); the XML quantities per locale are proven in ReaderR6ATest.
        var expectedCount = ""
        compose.setContent {
            HadithlyTheme {
                expectedCount = androidx.compose.ui.platform.LocalContext.current.resources
                    .getQuantityString(
                        com.hadithly.app.R.plurals.reader_hadith_count,
                        10,
                        10,
                    )
                VolumeStartHeader(title = "Volume 2", hadithCount = 10)
            }
        }

        compose.onNodeWithText("Volume 2").assertIsDisplayed()
        compose.runOnIdle { assertTrue(expectedCount.isNotBlank()) }
        compose.onNodeWithText(expectedCount).assertIsDisplayed()
    }

    @Test
    fun chapterHeaderIsQuietNameOnly() {
        compose.setContent {
            HadithlyTheme {
                ReaderChapterHeader(title = "Belief", arabicTitle = "الإيمان")
            }
        }

        compose.onNodeWithTag("reader.chapterHeader").assertIsDisplayed()
        compose.onNodeWithText("Belief").assertIsDisplayed()
        compose.onNodeWithText("الإيمان").assertIsDisplayed()
        compose.onNodeWithText("Chapter", substring = true).assertDoesNotExist()
    }

    @Test
    fun chapterHeaderOmitsArabicWhenMissing() {
        compose.setContent {
            HadithlyTheme {
                ReaderChapterHeader(title = "Belief", arabicTitle = null)
            }
        }
        compose.onNodeWithText("Belief").assertIsDisplayed()
    }

    @Test
    fun chapterHeaderOmitsArabicWhenSame() {
        compose.setContent {
            HadithlyTheme {
                ReaderChapterHeader(title = "Belief", arabicTitle = "Belief")
            }
        }
        // Exactly one Belief node: no duplicate Arabic second line.
        compose.onAllNodesWithText("Belief").assertCountEquals(1)
    }

    @Test
    fun pagePillsKeepChevronsAdjacentAndNameVolumeAtEdge() {
        var followed: ReaderPagePills.Pill? = null
        compose.setContent {
            HadithlyTheme {
                ReaderVolumePills(
                    policy = ReaderPagingPolicy(PageDirection.LTR),
                    state = ReaderPagePills.State(
                        previous = ReaderPagePills.Pill(
                            label = "Volume 1: Revelation",
                            target = ReaderPagePills.Target.VolumeLast("1"),
                            turn = ReaderPageTurn.PREVIOUS,
                            crossesVolume = true,
                        ),
                        next = ReaderPagePills.Pill(
                            label = "Page 2",
                            target = ReaderPagePills.Target.Page(1),
                            turn = ReaderPageTurn.NEXT,
                            crossesVolume = false,
                        ),
                    ),
                    onFollow = { followed = it },
                )
            }
        }

        compose.onNodeWithTag("reader.pagePills").assertIsDisplayed()
        compose.onNodeWithText("Volume 1: Revelation").assertIsDisplayed()
        compose.onNodeWithText("Page 2").assertIsDisplayed()
        compose.onNodeWithTag("reader.previousPage").assertIsDisplayed()
        compose.onNodeWithTag("reader.nextPage").assertIsDisplayed()
        compose.onNodeWithTag("reader.previousPage").performClick()
        compose.runOnIdle { assertEquals(ReaderPagePills.Target.VolumeLast("1"), followed?.target) }
    }

    @Test
    fun pagePillsHideAbsoluteOutwardEdge() {
        compose.setContent {
            HadithlyTheme {
                ReaderVolumePills(
                    policy = ReaderPagingPolicy(PageDirection.LTR),
                    state = ReaderPagePills.State(
                        previous = null,
                        next = ReaderPagePills.Pill(
                            label = "Volume 2: Belief",
                            target = ReaderPagePills.Target.VolumeFirst("2"),
                            turn = ReaderPageTurn.NEXT,
                            crossesVolume = true,
                        ),
                    ),
                    onFollow = {},
                )
            }
        }

        compose.onNodeWithTag("reader.pagePills").assertIsDisplayed()
        compose.onNodeWithText("Volume 2: Belief").assertIsDisplayed()
        compose.onNodeWithTag("reader.previousPage").assertDoesNotExist()
        compose.onNodeWithTag("reader.nextPage").assertIsDisplayed()
    }

    @Test
    fun longPressOpensMenuWithAllActions() {
        // A loaded non-English translation gates the Report item in.
        val loaded = TranslationUiState.Loaded(
            com.hadithly.app.core.data.ReaderTranslation(
                translationId = "t1",
                translation = "Rendering",
                source = "gemini_ai",
                sourceLabel = "AI",
            ),
        )
        compose.setContent { block(translationState = loaded) }

        compose.onNodeWithTag("reader.copy").assertDoesNotExist()
        compose.onNodeWithTag("reader.hadithBlock").performTouchInput {
            down(0, center)
            move()
            advanceEventTime(viewConfiguration.longPressTimeoutMillis)
            up(0)
        }
        compose.waitForIdle()

        for (tag in listOf(
            "reader.bookmark",
            "reader.favorite",
            "reader.note",
            "reader.copy",
            "reader.share",
            "reader.reportTranslation",
            "reader.suggestTranslation",
        )) {
            compose.onNodeWithTag(tag).assertIsDisplayed()
        }
    }

    // TalkBack custom actions ride on the same seven-action list as the
    // long-press menu (one code path in HadithBlock); their label-for-label
    // equivalence and invocation are proven in ReaderR6ATest, since this
    // Compose version keeps the CustomActions storage key private and the
    // test API cannot read it back. The menu side is proven on-device above.
}
