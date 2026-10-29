package com.atom.eval.references

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.FilterAlt
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.FilterAlt
import androidx.compose.material.icons.outlined.TextFields
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.layout.PaneAdaptedValue
import androidx.compose.material3.adaptive.navigation.BackNavigationBehavior
import androidx.compose.material3.adaptive.navigation.NavigableListDetailPaneScaffold
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.atom.eval.R
import com.atom.eval.ui.EmptyState
import com.atom.eval.ui.NoSearchResults
import com.atom.eval.ui.SearchField
import com.atom.eval.ui.paneScaffoldDirective
import com.atom.eval.ui.rememberCopyAction
import kotlinx.coroutines.launch

/**
 * The Références tab, as iOS ReferenceView: constants by domain and units, to browse
 * and search. A constant opens its detail beside the list on large screens, over it
 * on phones; units have no detail, so their list takes the whole width.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun ReferenceScreen(viewModel: ReferenceViewModel = viewModel()) {
    val list by viewModel.list.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val navigator = rememberListDetailPaneScaffoldNavigator<String>(
        scaffoldDirective = paneScaffoldDirective(maxPanes = if (viewModel.kind == ReferenceKind.Units) 1 else 2),
    )
    val detailIsShown = navigator.scaffoldValue[ListDetailPaneScaffoldRole.Detail] == PaneAdaptedValue.Expanded
    val listIsShown = navigator.scaffoldValue[ListDetailPaneScaffoldRole.List] == PaneAdaptedValue.Expanded
    val selectedId = navigator.currentDestination?.contentKey

    // Units have no detail: the list comes back alone.
    LaunchedEffect(viewModel.kind) {
        if (viewModel.kind != ReferenceKind.Units) return@LaunchedEffect
        while (navigator.currentDestination?.pane == ListDetailPaneScaffoldRole.Detail &&
            navigator.canNavigateBack(BackNavigationBehavior.PopLatest)
        ) {
            navigator.navigateBack(BackNavigationBehavior.PopLatest)
        }
    }

    NavigableListDetailPaneScaffold(
        navigator = navigator,
        listPane = {
            AnimatedPane {
                ReferenceListPane(
                    viewModel = viewModel,
                    list = list,
                    selectedId = selectedId.takeIf { detailIsShown },
                    onOpen = { id -> scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail, id) } },
                )
            }
        },
        detailPane = {
            AnimatedPane {
                val constant = remember(selectedId) { selectedId?.let(viewModel::constant) }
                if (constant != null) {
                    ConstantDetailPane(
                        constant = constant,
                        onClose = if (listIsShown) null else {
                            { scope.launch { navigator.navigateBack() } }
                        },
                    )
                } else {
                    EmptyState(
                        icon = Icons.AutoMirrored.Outlined.MenuBook,
                        title = stringResource(R.string.constants),
                        message = stringResource(R.string.choose_constant),
                    )
                }
            }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ReferenceListPane(
    viewModel: ReferenceViewModel,
    list: ReferenceListState,
    selectedId: String?,
    onOpen: (String) -> Unit,
) {
    Scaffold(
        topBar = {
            // As on iOS, the choice between constants and units takes the place of the title.
            CenterAlignedTopAppBar(
                title = { KindPicker(viewModel.kind, viewModel::select) },
                actions = {
                    if (viewModel.kind == ReferenceKind.Constants) {
                        DomainFilter(viewModel.categories, viewModel.categoryId, viewModel::filter)
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            SearchField(
                query = viewModel.query,
                onQueryChange = viewModel::updateQuery,
                placeholder = stringResource(R.string.search_references),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp),
            )
            if (!list.isLoaded) return@Column
            val isEmpty = when (list.kind) {
                ReferenceKind.Constants -> list.sections.isEmpty()
                ReferenceKind.Units -> list.units.isEmpty()
            }
            if (isEmpty) {
                NoSearchResults(viewModel.query)
                return@Column
            }
            val copy = rememberCopyAction()
            LazyColumn(Modifier.fillMaxSize()) {
                when (list.kind) {
                    ReferenceKind.Constants -> constants(list, selectedId, onOpen, copy)
                    ReferenceKind.Units -> units(list.units, copy)
                }
            }
        }
    }
}

@Composable
private fun KindPicker(kind: ReferenceKind, onSelect: (ReferenceKind) -> Unit) {
    val description = stringResource(R.string.reference_kind)
    SingleChoiceSegmentedButtonRow(Modifier.semantics { contentDescription = description }) {
        ReferenceKind.entries.forEachIndexed { index, option ->
            SegmentedButton(
                selected = option == kind,
                onClick = { onSelect(option) },
                shape = SegmentedButtonDefaults.itemShape(index, ReferenceKind.entries.size),
            ) {
                Text(
                    stringResource(
                        when (option) {
                            ReferenceKind.Constants -> R.string.constants
                            ReferenceKind.Units -> R.string.units
                        }
                    )
                )
            }
        }
    }
}

/** « Domaine »: all the constants, or those of one domain. */
@Composable
private fun DomainFilter(categories: List<CategoryState>, categoryId: String?, onFilter: (String?) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    val current = categories.firstOrNull { it.id == categoryId }?.title ?: stringResource(R.string.all_domains)
    Box {
        IconButton(
            onClick = { expanded = true },
            modifier = Modifier.semantics { stateDescription = current },
        ) {
            Icon(
                if (categoryId == null) Icons.Outlined.FilterAlt else Icons.Filled.FilterAlt,
                contentDescription = stringResource(R.string.domain),
            )
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            DomainItem(stringResource(R.string.all_domains), selected = categoryId == null) {
                expanded = false
                onFilter(null)
            }
            HorizontalDivider()
            for (category in categories) {
                DomainItem(category.title, selected = category.id == categoryId) {
                    expanded = false
                    onFilter(category.id)
                }
            }
        }
    }
}

@Composable
private fun DomainItem(title: String, selected: Boolean, onClick: () -> Unit) {
    DropdownMenuItem(
        text = { Text(title) },
        onClick = onClick,
        leadingIcon = {
            if (selected) Icon(Icons.Filled.Check, contentDescription = null) else Spacer(Modifier.size(24.dp))
        },
        modifier = Modifier.semantics { this.selected = selected },
    )
}

private fun LazyListScope.constants(
    list: ReferenceListState,
    selectedId: String?,
    onOpen: (String) -> Unit,
    copy: (String) -> Unit,
) {
    for (section in list.sections) {
        stickyHeader(key = "section-${section.categoryId}") { SectionHeader(section.title) }
        items(section.constants, key = { "constant-${it.id}" }) { constant ->
            ConstantRow(constant, isSelected = constant.id == selectedId, onOpen = onOpen, copy = copy)
        }
    }
    item(key = "footer") {
        Footer(
            pluralStringResource(R.plurals.constant_count, list.constantCount, list.constantCount),
            stringResource(R.string.constants_footer_offline),
            stringResource(R.string.constants_footer_case),
        )
    }
}

private fun LazyListScope.units(units: List<UnitRowState>, copy: (String) -> Unit) {
    stickyHeader(key = "units") { SectionHeader(stringResource(R.string.recognized_units)) }
    items(units, key = { "unit-${it.symbol}" }) { unit -> UnitRow(unit, copy) }
    item(key = "footer") {
        Footer(
            stringResource(R.string.units_footer_spacing),
            stringResource(R.string.units_footer_conversion),
            stringResource(R.string.units_footer_names),
        )
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier
            .fillMaxWidth()
            .background(MaterialTheme.colorScheme.surface)
            .padding(horizontal = 16.dp, vertical = 8.dp)
            .semantics { heading() },
    )
}

@Composable
private fun Footer(vararg paragraphs: String) {
    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        for (paragraph in paragraphs) {
            Text(paragraph, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun ConstantRow(constant: ConstantRowState, isSelected: Boolean, onOpen: (String) -> Unit, copy: (String) -> Unit) {
    var showsMenu by remember { mutableStateOf(false) }
    val copyValue = stringResource(R.string.copy_value)
    val copyIdentifier = stringResource(R.string.copy_identifier)
    Box {
        ListItem(
            headlineContent = { Text(constant.name) },
            supportingContent = {
                Text(
                    "${constant.symbol} = ${constant.valueText}",
                    style = MaterialTheme.typography.bodyMedium.copy(fontFeatureSettings = "tnum"),
                    modifier = Modifier.semantics { contentDescription = constant.spokenLine },
                )
            },
            colors = ListItemDefaults.colors(
                containerColor = if (isSelected) MaterialTheme.colorScheme.secondaryContainer
                else MaterialTheme.colorScheme.surface,
            ),
            modifier = Modifier
                .combinedClickable(onLongClick = { showsMenu = true }, onClick = { onOpen(constant.id) })
                .semantics {
                    customActions = listOf(
                        CustomAccessibilityAction(copyValue) { copy(constant.valueText); true },
                        CustomAccessibilityAction(copyIdentifier) { copy(constant.id); true },
                    )
                },
        )
        DropdownMenu(expanded = showsMenu, onDismissRequest = { showsMenu = false }) {
            DropdownMenuItem(
                text = { Text(copyValue) },
                leadingIcon = { Icon(Icons.Outlined.ContentCopy, contentDescription = null) },
                onClick = { showsMenu = false; copy(constant.valueText) },
            )
            DropdownMenuItem(
                text = { Text(copyIdentifier) },
                leadingIcon = { Icon(Icons.Outlined.TextFields, contentDescription = null) },
                onClick = { showsMenu = false; copy(constant.id) },
            )
        }
    }
}

/** A unit has nothing more to show: a touch offers to copy its symbol. */
@Composable
private fun UnitRow(unit: UnitRowState, copy: (String) -> Unit) {
    var showsMenu by remember { mutableStateOf(false) }
    val copySymbol = stringResource(R.string.copy_symbol)
    Box {
        ListItem(
            headlineContent = { Text(unit.name) },
            supportingContent = {
                Text(
                    unit.valueText,
                    style = MaterialTheme.typography.bodySmall.copy(fontFeatureSettings = "tnum"),
                    modifier = Modifier.semantics { contentDescription = unit.spokenValue },
                )
            },
            trailingContent = {
                Text(unit.symbol, style = MaterialTheme.typography.bodyLarge, fontFamily = FontFamily.Monospace)
            },
            modifier = Modifier.combinedClickable(
                onClickLabel = copySymbol,
                onLongClick = { showsMenu = true },
                onClick = { showsMenu = true },
            ),
        )
        DropdownMenu(expanded = showsMenu, onDismissRequest = { showsMenu = false }) {
            DropdownMenuItem(
                text = { Text(copySymbol) },
                leadingIcon = { Icon(Icons.Outlined.ContentCopy, contentDescription = null) },
                onClick = { showsMenu = false; copy(unit.symbol) },
            )
        }
    }
}
