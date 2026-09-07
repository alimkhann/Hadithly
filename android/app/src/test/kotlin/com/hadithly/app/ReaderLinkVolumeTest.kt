package com.hadithly.app

import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.features.reader.ReaderViewModel
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * F3: a canonical link carries no volume, so the reader locates the volume
 * holding the hadith from the source-provided outline counts.
 */
class ReaderLinkVolumeTest {
    private val outline = listOf(
        OutlineVolume(volumeId = "1", title = "Volume 1", hadithCount = 7.0),
        OutlineVolume(volumeId = "2", title = "Volume 2", hadithCount = 51.0),
        OutlineVolume(volumeId = "3", title = "Volume 3", hadithCount = 44.0),
    )

    @Test
    fun resolvesVolumeBoundaries() {
        assertEquals("1", ReaderViewModel.volumeIdForHadithNumber("1", outline))
        assertEquals("1", ReaderViewModel.volumeIdForHadithNumber("7", outline))
        assertEquals("2", ReaderViewModel.volumeIdForHadithNumber("8", outline))
        assertEquals("2", ReaderViewModel.volumeIdForHadithNumber("57", outline))
        assertEquals("2", ReaderViewModel.volumeIdForHadithNumber("58", outline))
        assertEquals("3", ReaderViewModel.volumeIdForHadithNumber("59", outline))
        assertEquals("3", ReaderViewModel.volumeIdForHadithNumber("102", outline))
    }

    @Test
    fun dottedSubreferenceUsesIntegerPart() {
        assertEquals("1", ReaderViewModel.volumeIdForHadithNumber("4.5", outline))
    }

    @Test
    fun staleNumbersFallBackToStart() {
        assertNull(ReaderViewModel.volumeIdForHadithNumber("103", outline))
        assertNull(ReaderViewModel.volumeIdForHadithNumber("9999", outline))
        assertNull(ReaderViewModel.volumeIdForHadithNumber("zero", outline))
        // A null result keeps the reader on the first volume at page 1.
    }
}
