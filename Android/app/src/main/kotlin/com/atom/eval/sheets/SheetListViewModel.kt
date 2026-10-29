package com.atom.eval.sheets

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider.AndroidViewModelFactory.Companion.APPLICATION_KEY
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.atom.eval.EvalApplication
import com.atom.eval.data.SheetStore
import eval.bridge.DeletedSheet
import eval.bridge.SheetLibrary
import eval.bridge.SheetSummary
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A row of the list: title, modification date and first displayed result. */
data class SheetRowState(
    val id: String,
    val title: String,
    /** Milliseconds since 1970. */
    val modifiedAt: Long,
    /** « E = 1000 J », null while it is computed or when there is none. */
    val preview: String?,
    /** The preview as TalkBack reads it. */
    val spokenPreview: String?,
)

data class SheetListState(
    /** False for a moment at launch, while the sheets are read. */
    val isLoaded: Boolean = false,
    /** The sheets matching the search, most recently modified first. */
    val rows: List<SheetRowState> = emptyList(),
    /** No sheet at all, whatever the search: « Aucune feuille ». */
    val isLibraryEmpty: Boolean = false,
)

data class ExampleCategoryState(val id: String, val title: String, val examples: List<ExampleState>)

data class ExampleState(val id: String, val title: String, val summary: String)

/**
 * The Calcul tab's list of sheets, as iOS SheetListView. Main thread, like the
 * library; the results shown in the rows are computed in the background.
 */
class SheetListViewModel(private val store: SheetStore) : ViewModel() {
    /** The search, kept in Compose state so that the field follows typing at once. */
    var query by mutableStateOf("")
        private set

    private val library: SheetLibrary get() = store.requireLibrary()

    /** Previews of sheets that are not open, by id, each for one modification date. */
    private val previews = MutableStateFlow<Map<String, Preview>>(emptyMap())
    private val evaluating = mutableSetOf<Pair<String, Long>>()
    private val previewEngine = Dispatchers.Default.limitedParallelism(1)

    private data class Preview(val modifiedAt: Long, val text: String?, val spoken: String?)

    /** One read of a summary: each property of a bridged object is a call into Swift. */
    private class Entry(val summary: SheetSummary) {
        val id = summary.id
        val title = summary.title
        val modifiedAt = summary.modifiedAt
        // An open sheet already has its results; others are evaluated in the background.
        val openPreview: Preview? = if (summary.isOpen) {
            summary.resultPreview().let { Preview(modifiedAt, it?.text, it?.spoken) }
        } else null
    }

    private val entries: StateFlow<List<Entry>?> =
        combine(store.library, store.changes, snapshotFlow { query }) { library, _, query ->
            library?.sheets(query)?.map(::Entry)
        }
            .onEach { entries -> entries?.forEach(::evaluatePreviewIfNeeded) }
            .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    val state: StateFlow<SheetListState> = combine(entries, previews) { entries, previews ->
        if (entries == null) return@combine SheetListState()
        SheetListState(
            isLoaded = true,
            rows = entries.map { entry ->
                val preview = entry.openPreview ?: previews[entry.id]?.takeIf { it.modifiedAt == entry.modifiedAt }
                SheetRowState(entry.id, entry.title, entry.modifiedAt, preview?.text, preview?.spoken)
            },
            isLibraryEmpty = store.library.value?.isEmpty ?: false,
        )
    }.stateIn(viewModelScope, SharingStarted.Eagerly, SheetListState())

    /** The sheet shown at launch: the most recent one. */
    val mostRecentSheetId: String? get() = store.library.value?.mostRecentSheetId

    val exampleCategories: List<ExampleCategoryState> by lazy {
        SheetLibrary.exampleCategories().map { category ->
            ExampleCategoryState(category.id, category.title, category.examples.map { ExampleState(it.id, it.title, it.summary) })
        }
    }

    fun updateQuery(text: String) {
        query = text
    }

    fun contains(id: String): Boolean = store.library.value?.contains(id) ?: false

    fun createSheet(): String = library.createSheet().also { store.changed() }

    fun createSheetFromExample(id: String): String? = library.createSheetFromExample(id).also { store.changed() }

    /** « Titre – copie », listed first. */
    fun duplicateSheet(id: String): String? = library.duplicateSheet(id).also { store.changed() }

    /** An empty title restores the automatic one. */
    fun renameSheet(id: String, title: String) {
        library.renameSheet(id, title)
        store.changed()
    }

    /** Deletes at once, as iOS: [restoreSheet] brings the sheet back. */
    fun deleteSheet(id: String): DeletedSheet? = library.deleteSheet(id).also { store.changed() }

    fun restoreSheet(sheet: DeletedSheet) {
        library.restoreSheet(sheet)
        store.changed()
    }

    fun sheetTitle(id: String): String? = library.sheet(id)?.title

    /** The title and text of a sheet, for « Partager ». */
    fun sharedSheet(id: String): Pair<String, String>? = library.sheet(id)?.let { it.title to it.source }

    private fun evaluatePreviewIfNeeded(entry: Entry) {
        if (entry.openPreview != null || previews.value[entry.id]?.modifiedAt == entry.modifiedAt) return
        val key = entry.id to entry.modifiedAt
        if (!evaluating.add(key)) return
        viewModelScope.launch {
            val preview = withContext(previewEngine) {
                entry.summary.resultPreview().let { Preview(entry.modifiedAt, it?.text, it?.spoken) }
            }
            evaluating.remove(key)
            previews.update { previews ->
                val current = previews[entry.id]
                if (current != null && current.modifiedAt > entry.modifiedAt) previews
                else previews + (entry.id to preview)
            }
        }
    }

    companion object {
        val Factory = viewModelFactory {
            initializer { SheetListViewModel((this[APPLICATION_KEY] as EvalApplication).sheetStore) }
        }
    }
}
