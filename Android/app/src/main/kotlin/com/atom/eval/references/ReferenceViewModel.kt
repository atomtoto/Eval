package com.atom.eval.references

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import eval.bridge.ConstantItem
import eval.bridge.ReferenceCatalog
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.withContext

enum class ReferenceKind { Constants, Units }

data class CategoryState(val id: String, val title: String)

data class ConstantRowState(
    /** What to type in a formula, such as `k_B`. */
    val id: String,
    val symbol: String,
    val name: String,
    val valueText: String,
    /** « c égale 299 792 458 mètres par seconde ». */
    val spokenLine: String,
)

data class ConstantSectionState(val categoryId: String, val title: String, val constants: List<ConstantRowState>)

data class UnitRowState(val symbol: String, val name: String, val valueText: String, val spokenValue: String)

/** Everything the detail of a constant shows. */
data class ConstantDetailState(
    val id: String,
    val symbol: String,
    val name: String,
    val detail: String,
    val valueText: String,
    val spokenValue: String,
    val aliases: List<String>,
    /** « Exacte », « Mesurée » or « Conventionnelle ». */
    val natureTitle: String,
    val sourceName: String,
    val sourceUrl: String?,
)

data class ReferenceListState(
    /** False until the first search is done. */
    val isLoaded: Boolean = false,
    /** The kind these results are for. */
    val kind: ReferenceKind = ReferenceKind.Constants,
    val sections: List<ConstantSectionState> = emptyList(),
    val constantCount: Int = 0,
    val units: List<UnitRowState> = emptyList(),
)

/** The Références tab, as iOS ReferenceCatalogView: constants by domain, and units. */
@OptIn(ExperimentalCoroutinesApi::class)
class ReferenceViewModel : ViewModel() {
    /** Compose state, so that the search field and the segmented buttons follow input at once. */
    var query by mutableStateOf("")
        private set
    var kind by mutableStateOf(ReferenceKind.Constants)
        private set
    /** The « Domaine » filter; null for « Tous les domaines ». */
    var categoryId by mutableStateOf<String?>(null)
        private set

    val categories: List<CategoryState> by lazy {
        ReferenceCatalog.categories().map { CategoryState(it.id, it.title) }
    }

    /** The catalog is searched away from the main thread, which only shows the results. */
    val list: StateFlow<ReferenceListState> = snapshotFlow { Triple(kind, query, categoryId) }
        .mapLatest { (kind, query, categoryId) -> withContext(Dispatchers.Default) { search(kind, query, categoryId) } }
        .stateIn(viewModelScope, SharingStarted.Eagerly, ReferenceListState())

    fun updateQuery(text: String) {
        query = text
    }

    fun select(kind: ReferenceKind) {
        this.kind = kind
    }

    fun filter(categoryId: String?) {
        this.categoryId = categoryId
    }

    /** A constant by its input name, for its detail pane. */
    fun constant(id: String): ConstantDetailState? = ReferenceCatalog.constant(id)?.let(::detail)

    private fun search(kind: ReferenceKind, query: String, categoryId: String?): ReferenceListState =
        when (kind) {
            ReferenceKind.Constants -> {
                val sections = ReferenceCatalog.constantSections(query, categoryId).map { section ->
                    ConstantSectionState(section.categoryId, section.title, section.constants.map(::row))
                }
                ReferenceListState(isLoaded = true, kind = kind, sections = sections, constantCount = sections.sumOf { it.constants.size })
            }
            ReferenceKind.Units -> ReferenceListState(
                isLoaded = true,
                kind = kind,
                units = ReferenceCatalog.units(query).map { UnitRowState(it.symbol, it.name, it.valueText, it.spokenValue) },
            )
        }

    private fun row(item: ConstantItem) = ConstantRowState(item.id, item.symbol, item.name, item.valueText, item.spokenLine)

    private fun detail(item: ConstantItem) = ConstantDetailState(
        id = item.id,
        symbol = item.symbol,
        name = item.name,
        detail = item.detail,
        valueText = item.valueText,
        spokenValue = item.spokenValue,
        aliases = item.aliases,
        natureTitle = item.natureTitle,
        sourceName = item.sourceName,
        sourceUrl = item.sourceUrl,
    )
}
