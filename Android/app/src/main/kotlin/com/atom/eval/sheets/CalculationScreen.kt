package com.atom.eval.sheets

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material3.Button
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.ExperimentalMaterial3AdaptiveApi
import androidx.compose.material3.adaptive.layout.AnimatedPane
import androidx.compose.material3.adaptive.layout.ListDetailPaneScaffoldRole
import androidx.compose.material3.adaptive.layout.PaneAdaptedValue
import androidx.compose.material3.adaptive.layout.ThreePaneScaffoldDestinationItem
import androidx.compose.material3.adaptive.navigation.BackNavigationBehavior
import androidx.compose.material3.adaptive.navigation.NavigableListDetailPaneScaffold
import androidx.compose.material3.adaptive.navigation.rememberListDetailPaneScaffoldNavigator
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalAccessibilityManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.atom.eval.R
import com.atom.eval.sheet.SheetScreen
import com.atom.eval.ui.EmptyState
import com.atom.eval.ui.paneScaffoldDirective
import com.atom.eval.ui.shareText
import eval.bridge.SheetLibrary
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The Calcul tab, as iOS SheetSplitView: the sheet list beside the selected sheet
 * on large screens; on phones the sheet opens over the list, with a back arrow and
 * the predictive back gesture. The app opens on the most recent sheet, as on iOS.
 */
@OptIn(ExperimentalMaterial3AdaptiveApi::class)
@Composable
fun CalculationScreen(viewModel: SheetListViewModel = viewModel(factory = SheetListViewModel.Factory)) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    // The sheets are read in a moment at launch; the window background shows meanwhile.
    if (!state.isLoaded) return

    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val snackbarHostState = remember { SnackbarHostState() }
    val accessibility = LocalAccessibilityManager.current
    var selectedId by rememberSaveable { mutableStateOf(viewModel.mostRecentSheetId) }
    var showsExamples by rememberSaveable { mutableStateOf(false) }
    var renamingId by rememberSaveable { mutableStateOf<String?>(null) }
    val navigator = rememberListDetailPaneScaffoldNavigator(
        scaffoldDirective = paneScaffoldDirective(),
        initialDestinationHistory = listOfNotNull(
            ThreePaneScaffoldDestinationItem<Nothing>(ListDetailPaneScaffoldRole.List),
            selectedId?.let { ThreePaneScaffoldDestinationItem<Nothing>(ListDetailPaneScaffoldRole.Detail) },
        ),
    )
    val listIsShown = navigator.scaffoldValue[ListDetailPaneScaffoldRole.List] == PaneAdaptedValue.Expanded
    val detailIsShown = navigator.scaffoldValue[ListDetailPaneScaffoldRole.Detail] == PaneAdaptedValue.Expanded

    // Choosing another sheet replaces the one shown: the back history stays list → sheet.
    fun open(id: String) {
        selectedId = id
        if (navigator.currentDestination?.pane != ListDetailPaneScaffoldRole.Detail) {
            scope.launch { navigator.navigateTo(ListDetailPaneScaffoldRole.Detail) }
        }
    }

    // Deletes at once and offers Annuler for a few seconds, as on iOS, instead of asking first.
    fun delete(row: SheetRowState) {
        val deleted = viewModel.deleteSheet(row.id) ?: return
        if (selectedId == row.id) {
            selectedId = null
            if (navigator.currentDestination?.pane == ListDetailPaneScaffoldRole.Detail) {
                scope.launch { navigator.navigateBack(BackNavigationBehavior.PopLatest) }
            }
        }
        // Longer when the user needs more time, with TalkBack for instance.
        val undoMillis = accessibility?.calculateRecommendedTimeoutMillis(
            SheetLibrary.deletionUndoMillis, containsIcons = false, containsText = true, containsControls = true,
        ) ?: SheetLibrary.deletionUndoMillis
        scope.launch {
            snackbarHostState.currentSnackbarData?.dismiss()
            val result = withTimeoutOrNull(undoMillis) {
                snackbarHostState.showSnackbar(
                    message = context.getString(R.string.sheet_deleted, deleted.title),
                    actionLabel = context.getString(R.string.cancel),
                    duration = SnackbarDuration.Indefinite,
                )
            }
            if (result == SnackbarResult.ActionPerformed) viewModel.restoreSheet(deleted)
        }
    }

    val actions = SheetRowActions(
        open = ::open,
        rename = { renamingId = it.id },
        duplicate = { id -> viewModel.duplicateSheet(id) },
        share = { id -> viewModel.sharedSheet(id)?.let { (title, source) -> context.shareText(source, title = title) } },
        delete = ::delete,
    )

    NavigableListDetailPaneScaffold(
        navigator = navigator,
        listPane = {
            AnimatedPane {
                SheetListPane(
                    state = state,
                    query = viewModel.query,
                    onQueryChange = viewModel::updateQuery,
                    selectedId = selectedId.takeIf { detailIsShown },
                    snackbarHostState = snackbarHostState,
                    onCreate = { open(viewModel.createSheet()) },
                    onShowExamples = { showsExamples = true },
                    actions = actions,
                )
            }
        },
        detailPane = {
            AnimatedPane {
                val id = selectedId
                if (id != null && viewModel.contains(id)) {
                    // A new screen for each sheet, as `.id(id)` on iOS.
                    key(id) {
                        SheetScreen(
                            sheetId = id,
                            onClose = if (listIsShown) null else {
                                { scope.launch { navigator.navigateBack() } }
                            },
                            onOpenSheet = ::open,
                        )
                    }
                } else {
                    EmptyState(
                        icon = Icons.Outlined.Description,
                        title = stringResource(R.string.no_sheet),
                        message = stringResource(R.string.no_sheet_selected_message),
                    ) {
                        Button(onClick = { open(viewModel.createSheet()) }) { Text(stringResource(R.string.new_sheet)) }
                    }
                }
            }
        },
    )

    if (showsExamples) {
        ExamplePickerSheet(
            categories = viewModel.exampleCategories,
            onChoose = { example ->
                showsExamples = false
                viewModel.createSheetFromExample(example)?.let(::open)
            },
            onDismiss = { showsExamples = false },
        )
    }

    renamingId?.let { id ->
        RenameSheetDialog(
            currentTitle = remember(id) { viewModel.sheetTitle(id) ?: "" },
            onRename = { title ->
                renamingId = null
                viewModel.renameSheet(id, title)
            },
            onDismiss = { renamingId = null },
        )
    }
}
