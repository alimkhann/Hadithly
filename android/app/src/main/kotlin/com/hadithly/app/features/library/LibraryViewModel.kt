package com.hadithly.app.features.library

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.core.data.CollectionProgressSummary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** One compact progress stream; no chapter-rich outline subscriptions. */
class LibraryViewModel : ViewModel() {

    private val _loading = MutableStateFlow(true)
    val loading: StateFlow<Boolean> = _loading
    private val _summaries = MutableStateFlow<Map<String, CollectionProgressSummary>>(emptyMap())
    val summaries: StateFlow<Map<String, CollectionProgressSummary>> = _summaries

    private val app: HadithlyApplication by lazy {
        // ViewModel created from a composable inside the app process.
        HadithlyApplication.instance()
    }

    init {
        viewModelScope.launch(Dispatchers.IO) {
            try {
                app.repository.subscribe<List<CollectionProgressSummary>>("library:listCollectionProgressSummaries")
                    .collect { summaries ->
                        _summaries.value = summaries.associateBy { it.collectionSlug }
                        _loading.value = false
                    }
            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                _loading.value = false
            }
        }

    }

    /** Continue-reading card, driven by the shared library facade. */
    val progress = app.library.progress
}
