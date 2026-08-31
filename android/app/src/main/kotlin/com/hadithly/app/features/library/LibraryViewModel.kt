package com.hadithly.app.features.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.data.CollectionOutlineResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Watches the cached volume outlines so the Library can show counts per
 * collection. Reads only the `collectionOutlines` cache — collections never
 * opened stay quiet with no counts. Mirrors iOS LibraryModel.
 */
class LibraryViewModel : ViewModel() {

    data class VolumeCounts(val volumes: Int, val hadiths: Int)

    private val _counts = MutableStateFlow<Map<String, VolumeCounts>>(emptyMap())
    val counts: StateFlow<Map<String, VolumeCounts>> = _counts

    private val app: HadithlyApplication by lazy {
        // ViewModel created from a composable inside the app process.
        HadithlyApplication.instance()
    }

    init {
        for ((slug, _) in Collections.all) {
            viewModelScope.launch(Dispatchers.IO) {
                app.repository.subscribe<CollectionOutlineResult?>(
                    "collections:getOutline",
                    mapOf("collectionSlug" to slug),
                ).collect { outline ->
                    if (outline != null && outline.volumes.isNotEmpty()) {
                        val totalHadiths = outline.volumes.sumOf { it.hadithCount }.toInt()
                        _counts.update {
                            it + (slug to VolumeCounts(outline.volumes.size, totalHadiths))
                        }
                    }
                }
            }
        }
    }

    /** Continue-reading card, driven by the shared library facade. */
    val progress = app.library.progress
}
