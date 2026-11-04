package com.hadithly.app.features.reader

import android.app.UiAutomation
import android.content.ContextWrapper
import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.provider.Settings
import androidx.activity.compose.setContent
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.MainActivity
import com.hadithly.app.core.data.AuthenticityClaim
import com.hadithly.app.core.data.CollectionOutlineResult
import com.hadithly.app.core.data.GuestDataStore
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderPageResult
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.core.data.UserLibraryModel
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.theme.LocalizedPreview
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

class ReaderOrientationTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()

    @Test fun readerRotationLockAndExitRetainHadith() {
        val ui = InstrumentationRegistry.getInstrumentation().uiAutomation
        val activity = compose.activity
        val app = activity.application as HadithlyApplication
        assertNull(com.clerk.api.Clerk.user)
        val directory = kotlin.io.path.createTempDirectory(app.cacheDir.toPath(), "reader-orientation").toFile()
        val context = object : ContextWrapper(app) { override fun getFilesDir() = directory }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val library = UserLibraryModel(GuestDataStore(context), scope)
        val owner = object : ViewModelStoreOwner { override val viewModelStore = ViewModelStore() }
        val readerOpen = mutableStateOf(true)
        val originalOrientation = compose.runOnIdle { activity.requestedOrientation }
        val autoRotate = Settings.System.getInt(app.contentResolver, Settings.System.ACCELEROMETER_ROTATION, 1) != 0
        val userRotation = Settings.System.getInt(app.contentResolver, Settings.System.USER_ROTATION, 0)
        val page = ReaderPageResult(
            items = listOf(hadith("57", "الحديث الأول"), hadith("58", "الحديث المقصود")),
            page = 1.0, pageSize = 2.0, totalPages = 1.0, hasMore = false,
        )
        lateinit var model: ReaderViewModel

        fun rotate(request: Int, expected: Int) {
            assertTrue(ui.setRotation(request))
            compose.waitUntil(5_000) { activity.resources.configuration.orientation == expected }
            compose.waitForIdle()
        }
        fun assertPosition() {
            compose.waitUntil(5_000) { model.state.value.verticalLanding == null }
            compose.runOnIdle {
                assertSame(activity, compose.activity)
                assertEquals("58", model.positionedHadith()?.providerHadithId)
            }
            compose.onNodeWithText("الحديث المقصود", substring = true, useUnmergedTree = true).assertIsDisplayed()
        }

        try {
            rotate(UiAutomation.ROTATION_FREEZE_0, Configuration.ORIENTATION_PORTRAIT)
            compose.runOnUiThread {
                model = ReaderViewModel(app, "bukhari", null, "58", null, ReaderTargetSource.CANONICAL_LINK,
                    library = library,
                    translationReads = ReaderTranslationReads(defaults = { _, _ -> emptyList() },
                        publications = { kotlinx.coroutines.flow.flow { kotlinx.coroutines.awaitCancellation() } }),
                    outlineLoader = { CollectionOutlineResult(listOf(OutlineVolume("1", "Rotation fixture", hadithCount = 2.0))) },
                    pageLoader = { _, _, _ -> page })
                owner.viewModelStore.put("reader-58", model)
                activity.setContent {
                    CompositionLocalProvider(LocalViewModelStoreOwner provides owner) {
                        LocalizedPreview(ReaderTheme.DARK, "en") {
                            if (readerOpen.value) {
                                ReaderScreen("bukhari", "Rotation fixture", null, "58", null,
                                    ReaderTargetSource.CANONICAL_LINK, 58L, { readerOpen.value = false })
                            } else {
                                Text("Reader closed")
                            }
                        }
                    }
                }
            }
            compose.waitUntil(10_000) { !model.state.value.isLoadingPage && model.positionedHadith()?.providerHadithId == "58" }
            assertPosition()

            rotate(UiAutomation.ROTATION_FREEZE_90, Configuration.ORIENTATION_LANDSCAPE)
            assertPosition()
            val corner = compose.onNodeWithTag("reader.orientation.corner")
            corner.assertIsDisplayed().assertContentDescriptionEquals("Lock orientation").performClick()
            corner.assertContentDescriptionEquals("Unlock orientation")
            compose.runOnIdle { assertEquals(ActivityInfo.SCREEN_ORIENTATION_LOCKED, activity.requestedOrientation) }

            assertTrue(ui.setRotation(UiAutomation.ROTATION_FREEZE_0))
            compose.mainClock.advanceTimeBy(3_500)
            compose.runOnIdle { assertEquals(Configuration.ORIENTATION_LANDSCAPE, activity.resources.configuration.orientation) }
            corner.assertDoesNotExist()
            assertPosition()

            compose.onNodeWithContentDescription("Open reader menu").performClick()
            val menu = compose.onNodeWithTag("reader.menu.orientation")
            menu.assertContentDescriptionEquals("Unlock orientation").performClick()
            compose.waitUntil(5_000) { activity.resources.configuration.orientation == Configuration.ORIENTATION_PORTRAIT }
            assertPosition()
            compose.runOnIdle { assertEquals(originalOrientation, activity.requestedOrientation) }

            menu.assertContentDescriptionEquals("Lock orientation").performClick()
            compose.onNodeWithContentDescription("Back").performClick()
            compose.onNodeWithText("Reader closed").assertIsDisplayed()
            compose.waitUntil(5_000) { library.progressFor("bukhari")?.position?.anchor?.providerHadithId == "58" }
            compose.runOnIdle { assertEquals(originalOrientation, activity.requestedOrientation) }
            rotate(UiAutomation.ROTATION_FREEZE_90, Configuration.ORIENTATION_LANDSCAPE)
            compose.onNodeWithText("Reader closed").assertIsDisplayed()
        } finally {
            ui.setRotation(userRotation)
            if (autoRotate) ui.setRotation(UiAutomation.ROTATION_UNFREEZE)
            compose.runOnUiThread { owner.viewModelStore.clear(); scope.cancel() }
            directory.deleteRecursively()
        }
    }

    private fun hadith(number: String, text: String) = ReaderHadith(
        _id = "rotation-$number", provider = "sunnah_now", canonicalId = "sunnah_now:bukhari:$number",
        providerHadithId = number, collectionSlug = "bukhari", volumeId = "1",
        arabicText = "$text ".repeat(120), englishText = "Fixture hadith $number",
        referenceDisplay = "Bukhari – $number", collectionName = "Bukhari",
        authenticity = AuthenticityClaim("unknown", claimScope = "hadith", sourceLabel = "Fixture",
            sourceName = "Fixture", sourceUrl = "", verificationMethod = "fixture"),
    )
}
