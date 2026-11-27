package com.atom.eval.sheet

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.consumeWindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import com.atom.eval.ui.icons.MaterialSymbols as Icons
import com.atom.eval.ui.icons.MaterialSymbols.AutoMirrored.Outlined.Redo
import com.atom.eval.ui.icons.MaterialSymbols.AutoMirrored.Outlined.Undo
import com.atom.eval.ui.icons.MaterialSymbols.Outlined.Add
import com.atom.eval.ui.icons.MaterialSymbols.Outlined.Delete
import com.atom.eval.ui.icons.MaterialSymbols.Outlined.DocumentScanner
import com.atom.eval.ui.icons.MaterialSymbols.Outlined.MoreVert
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.atom.eval.R
import com.atom.eval.sheets.ExampleCategoryState
import com.atom.eval.sheets.ExamplePickerSheet
import com.atom.eval.sheets.ExampleState
import com.atom.eval.sheets.RenameSheetDialog
import com.atom.eval.appSettings
import com.atom.eval.data.FormulaInputMode
import com.atom.eval.settings.SettingsDialog
import com.atom.eval.help.HelpDialog
import com.atom.eval.scanner.FormulaScanner
import com.atom.eval.sheetStore
import com.atom.eval.ui.BackButton
import com.atom.eval.ui.shareText
import eval.bridge.SheetLibrary

/**
 * One sheet, in the detail pane of the Calcul tab (iOS NotebookView): its lines with
 * their results, edited in place one at a time.
 *
 * @param sheetId the sheet to show; the caller gives each sheet its own screen.
 * @param onClose returns to the sheet list; null when the list is already beside the sheet.
 * @param onOpenSheet shows another sheet in its place, such as a copy.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SheetScreen(
    sheetId: String,
    onClose: (() -> Unit)?,
    onOpenSheet: (String) -> Unit,
    modifier: Modifier = Modifier,
) {
    val store = LocalContext.current.sheetStore
    val viewModel = viewModel(key = sheetId) { SheetViewModel(store, sheetId) }
    val state by viewModel.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val focusManager = LocalFocusManager.current
    val listState = rememberLazyListState()
    val field = remember { EditedField() }
    var isReordering by rememberSaveable { mutableStateOf(false) }
    var isRenaming by rememberSaveable { mutableStateOf(false) }
    var confirmsClear by rememberSaveable { mutableStateOf(false) }
    var showsSettings by rememberSaveable { mutableStateOf(false) }
    var showsHelp by rememberSaveable { mutableStateOf(false) }
    var showsTextEditor by rememberSaveable { mutableStateOf(false) }
    var showsExamples by rememberSaveable { mutableStateOf(false) }
    var plot by remember { mutableStateOf<PlotRequest?>(null) }
    // The scanner, and the line below which its lines go (the end of the sheet for null).
    var scansAfter by remember { mutableStateOf<String?>(null) }
    var isScanning by rememberSaveable { mutableStateOf(false) }
    val settings = context.appSettings
    val showsLineNumbers by settings.lineNumbers.collectAsStateWithLifecycle()
    val inputMode by settings.inputMode.collectAsStateWithLifecycle()
    val significantDigits by settings.significantDigits.collectAsStateWithLifecycle()
    // Results are written again with the number of digits chosen in « Réglages ».
    LaunchedEffect(significantDigits) { viewModel.refresh() }
    val subject = stringResource(R.string.sheet_subject)
    // The issue of the whole sheet, when there is one, comes before the lines.
    val firstLineItem = if (state.sheetIssue != null) 1 else 0
    // As on iOS, the « Nouvelle ligne » row stands in for a blank last line being edited,
    // whose field shows the same placeholder in the same place.
    val lastLine = state.lines.lastOrNull()
    val showsNewLineRow = !isReordering &&
        !(lastLine != null && lastLine.isEditing && lastLine.source.isBlank())

    // Leaving the sheet validates the line being edited, as on iOS.
    DisposableEffect(viewModel) { onDispose { state.editingLineId?.let(viewModel::endEditing) } }

    // A line just added or edited comes into view if it is not; the focused field
    // then stays above the keyboard by itself.
    LaunchedEffect(state.editingLineId, state.revealRequestId) {
        val lineId = state.editingLineId ?: state.revealLineId ?: return@LaunchedEffect
        val index = state.lines.indexOfFirst { it.id == lineId }
        if (index < 0) return@LaunchedEffect
        val layout = listState.layoutInfo
        val shown = layout.visibleItemsInfo.firstOrNull { it.index == firstLineItem + index }
        if (shown == null || shown.offset < 0 || shown.offset + shown.size > layout.viewportEndOffset) {
            listState.animateScrollToItem(firstLineItem + index)
        }
    }

    Scaffold(
        modifier = modifier,
        topBar = {
            TopAppBar(
                title = {
                    Text(
                        state.title,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.clickable(onClickLabel = stringResource(R.string.rename)) { isRenaming = true },
                    )
                },
                navigationIcon = { onClose?.let { BackButton(it) } },
                actions = {
                    if (isReordering) {
                        TextButton(onClick = { isReordering = false }) { Text(stringResource(R.string.done)) }
                    } else {
                        UndoButtons(state, viewModel)
                        SheetMenu(
                            canUndo = state.canUndo,
                            canRedo = state.canRedo,
                            undoName = state.undoActionName,
                            redoName = state.redoActionName,
                            onUndo = viewModel::undo,
                            onRedo = viewModel::redo,
                            onRename = { isRenaming = true },
                            onDuplicate = { viewModel.duplicateSheet()?.let(onOpenSheet) },
                            onShare = { results -> context.shareText(viewModel.sharedText(results), state.title, subject) },
                            onReorder = { isReordering = true },
                            onClear = { confirmsClear = true },
                            onEditAsText = { showsTextEditor = true },
                            onExamples = { showsExamples = true },
                            onSettings = { showsSettings = true },
                            onScan = {
                                scansAfter = null
                                isScanning = true
                            },
                            onHelp = { showsHelp = true },
                        )
                    }
                },
            )
        },
        floatingActionButton = {
            // While a line is edited, Return adds the next one.
            if (state.editingLineId == null && !isReordering) {
                // A tap adds a line; a long press offers the scanner, as the + of iOS does.
                var showsAddMenu by rememberSaveable { mutableStateOf(false) }
                Box {
                    FloatingActionButton(
                        onClick = viewModel::newLine,
                        modifier = Modifier.combinedClickable(
                            onClick = viewModel::newLine,
                            onLongClickLabel = stringResource(R.string.scan_formula),
                            onLongClick = { showsAddMenu = true },
                        ),
                    ) {
                        Icon(Icons.Outlined.Add, contentDescription = stringResource(R.string.add_line))
                    }
                    DropdownMenu(expanded = showsAddMenu, onDismissRequest = { showsAddMenu = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.scan_formula)) },
                            leadingIcon = { Icon(Icons.Outlined.DocumentScanner, contentDescription = null) },
                            onClick = {
                                showsAddMenu = false
                                scansAfter = null
                                isScanning = true
                            },
                        )
                    }
                }
            }
        },
    ) { padding ->
        Box(
            Modifier
                .fillMaxSize()
                .padding(padding)
                .consumeWindowInsets(padding)
                .imePadding()
                // A tap outside the lines validates the edited one, as on iOS.
                .pointerInput(Unit) { detectTapGestures { focusManager.clearFocus() } },
        ) {
            // Room at the end for the floating button, or the keyboard bar.
            val isTyping = state.editingLineId != null && !isReordering
            // While a line is edited, the list ends above the keyboard bar, so the
            // field it keeps in view is never under the bar.
            LazyColumn(
                Modifier.fillMaxSize().padding(bottom = if (isTyping) 72.dp else 0.dp),
                state = listState,
                contentPadding = PaddingValues(bottom = if (isTyping) 8.dp else 88.dp),
            ) {
                state.sheetIssue?.let { issue ->
                    item(key = "issue") {
                        Text(
                            issue,
                            color = MaterialTheme.colorScheme.error,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }
                }
                itemsIndexed(state.lines, key = { _, line -> line.id }) { index, line ->
                    DeletableLine(enabled = !line.isEditing && !isReordering, onDelete = { viewModel.removeLine(line.id) }) {
                        SheetLineRow(
                            line = line,
                            viewModel = viewModel,
                            isReordering = isReordering,
                            isFirst = index == 0,
                            isLast = index == state.lines.lastIndex,
                            field = field,
                            showsLineNumber = showsLineNumbers,
                            inputMode = inputMode,
                            onPlot = { plot = it },
                        )
                    }
                }
                if (showsNewLineRow) {
                    item(key = "new-line") {
                        ListItem(
                            headlineContent = { Text(stringResource(R.string.new_line), color = MaterialTheme.colorScheme.primary) },
                            leadingContent = { Icon(Icons.Outlined.Add, contentDescription = null, tint = MaterialTheme.colorScheme.primary) },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                            modifier = Modifier.clickable(onClick = viewModel::newLine),
                        )
                    }
                }
                if (state.constants.isNotEmpty()) {
                    item(key = "constants") { SectionHeader(stringResource(R.string.recognized_constants)) }
                    items(state.constants, key = { "constant-" + it.id }) { constant ->
                        ListItem(
                            headlineContent = { Text("${constant.symbol} = ${constant.valueText}") },
                            supportingContent = { Text(constant.name) },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        )
                    }
                }
                if (state.symbolUnits.isNotEmpty()) {
                    item(key = "units") { SectionHeader(stringResource(R.string.symbols_read_as_units)) }
                    items(state.symbolUnits, key = { "unit-" + it.symbol }) { unit ->
                        ListItem(
                            headlineContent = { Text("${unit.symbol} = ${unit.valueText}") },
                            supportingContent = { Text(unit.name) },
                            colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        )
                    }
                    item(key = "units-footer") {
                        Text(
                            stringResource(R.string.symbols_read_as_units_footer),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                        )
                    }
                }
            }
            if (isTyping) {
                KeyboardBar(
                    variableNames = state.declaredNames,
                    math = if (inputMode == FormulaInputMode.Math) field.math else null,
                    onInsert = { kind, value -> field.insert(kind, value)?.let(viewModel::updateEditedLine) },
                    onShowReferences = { field.isPicking = true },
                    onScan = {
                        scansAfter = state.editingLineId
                        isScanning = true
                    },
                    onDone = { focusManager.clearFocus() },
                    modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 10.dp),
                )
            }
            // An evaluation that takes a while shows its progress, as on iOS.
            AnimatedVisibility(state.isEvaluating, modifier = Modifier.align(Alignment.TopCenter)) {
                LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        }
    }

    if (field.isPicking) {
        SymbolPicker(
            onPick = { kind, value ->
                val math = field.math
                if (inputMode == FormulaInputMode.Math && math != null) {
                    if (kind == "unit") math.type(" $value") else math.insertName(value)
                } else {
                    field.insert(kind, value)?.let(viewModel::updateEditedLine)
                }
                field.isPicking = false
            },
            onDismiss = { field.isPicking = false },
        )
    }
    if (showsSettings) SettingsDialog { showsSettings = false }
    if (showsHelp) HelpDialog { showsHelp = false }
    if (showsTextEditor) {
        TextSheetEditorDialog(
            source = viewModel.source,
            declaredNames = state.declaredNames,
            onApply = { text -> viewModel.editAsText(text); showsTextEditor = false },
            onDismiss = { showsTextEditor = false },
        )
    }
    if (showsExamples) {
        // As in the list's button, an example opens in a new sheet.
        val categories = remember { exampleCategories() }
        ExamplePickerSheet(
            categories = categories,
            onChoose = { exampleId ->
                showsExamples = false
                viewModel.createSheetFromExample(exampleId)?.let(onOpenSheet)
            },
            onDismiss = { showsExamples = false },
        )
    }
    // A ruler adjustment asks TalkBack to read the recalculated results.
    val view = LocalView.current
    LaunchedEffect(state.announcement) {
        val announcement = state.announcement ?: return@LaunchedEffect
        view.announceForAccessibility(announcement.second)
        viewModel.clearAnnouncement()
    }
    plot?.let { PlotDialog(it, viewModel) { plot = null } }
    if (isScanning) {
        FormulaScanner(
            declared = state.declaredNames,
            onLines = { lines ->
                isScanning = false
                viewModel.insertScannedLines(lines, scansAfter)
            },
            onDismiss = { isScanning = false },
        )
    }
    state.ruler?.let { ruler -> RulerSheet(ruler, viewModel, onDismiss = viewModel::hideRuler) }
    // The line of an open ruler stays in view above it.
    LaunchedEffect(state.ruler?.lineId) {
        val lineId = state.ruler?.lineId ?: return@LaunchedEffect
        val index = state.lines.indexOfFirst { it.id == lineId }
        if (index >= 0) listState.animateScrollToItem(firstLineItem + index)
    }
    if (isRenaming) {
        RenameSheetDialog(
            currentTitle = state.title,
            onRename = { viewModel.rename(it); isRenaming = false },
            onDismiss = { isRenaming = false },
        )
    }
    if (confirmsClear) {
        AlertDialog(
            onDismissRequest = { confirmsClear = false },
            title = { Text(stringResource(R.string.clear_sheet_title)) },
            text = { Text(stringResource(R.string.clear_sheet_message)) },
            confirmButton = {
                TextButton(onClick = { viewModel.clear(); confirmsClear = false }) {
                    Text(stringResource(R.string.clear), color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { confirmsClear = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

/** Undo and Redo, named after the step they undo or redo, as « Annuler Modifier la ligne ». */
@Composable
private fun UndoButtons(state: SheetUiState, viewModel: SheetViewModel) {
    val undo = state.undoActionName?.let { stringResource(R.string.undo_action, it) } ?: stringResource(R.string.undo)
    val redo = state.redoActionName?.let { stringResource(R.string.redo_action, it) } ?: stringResource(R.string.redo)
    IconButton(onClick = viewModel::undo, enabled = state.canUndo) {
        Icon(Icons.AutoMirrored.Outlined.Undo, contentDescription = undo)
    }
    IconButton(onClick = viewModel::redo, enabled = state.canRedo) {
        Icon(Icons.AutoMirrored.Outlined.Redo, contentDescription = redo)
    }
}

/** « Actions de la feuille », as the iOS menu of NotebookView. */
@Composable
private fun SheetMenu(
    canUndo: Boolean,
    canRedo: Boolean,
    undoName: String?,
    redoName: String?,
    onUndo: () -> Unit,
    onRedo: () -> Unit,
    onRename: () -> Unit,
    onDuplicate: () -> Unit,
    onShare: (includingResults: Boolean) -> Unit,
    onReorder: () -> Unit,
    onClear: () -> Unit,
    onEditAsText: () -> Unit,
    onExamples: () -> Unit,
    onSettings: () -> Unit,
    onScan: () -> Unit,
    onHelp: () -> Unit,
) {
    var isExpanded by rememberSaveable { mutableStateOf(false) }
    Box {
        IconButton(onClick = { isExpanded = true }) {
            Icon(Icons.Outlined.MoreVert, contentDescription = stringResource(R.string.sheet_more_actions))
        }
        DropdownMenu(expanded = isExpanded, onDismissRequest = { isExpanded = false }) {
            @Composable
            fun Item(text: Int, arg: String? = null, enabled: Boolean = true, action: () -> Unit) =
                DropdownMenuItem(
                    text = { Text(if (arg != null) stringResource(text, arg) else stringResource(text)) },
                    enabled = enabled,
                    onClick = { isExpanded = false; action() },
                )

            // Annuler and Rétablir, named after the step they undo or redo.
            Item(if (undoName != null) R.string.undo_action else R.string.undo, arg = undoName, enabled = canUndo) { onUndo() }
            Item(if (redoName != null) R.string.redo_action else R.string.redo, arg = redoName, enabled = canRedo) { onRedo() }
            HorizontalDivider()
            Item(R.string.scan_formula) { onScan() }
            Item(R.string.edit_as_text) { onEditAsText() }
            Item(R.string.new_from_example) { onExamples() }
            Item(R.string.rename) { onRename() }
            Item(R.string.duplicate) { onDuplicate() }
            Item(R.string.share_sheet) { onShare(true) }
            Item(R.string.share_without_results) { onShare(false) }
            HorizontalDivider()
            Item(R.string.reorder) { onReorder() }
            Item(R.string.clear_sheet) { onClear() }
            HorizontalDivider()
            Item(R.string.settings) { onSettings() }
            Item(R.string.help) { onHelp() }
        }
    }
}

/** The example sheets of « Nouvelle à partir d’un exemple », by domain. */
private fun exampleCategories(): List<ExampleCategoryState> =
    SheetLibrary.exampleCategories().map { category ->
        ExampleCategoryState(category.id, category.title, category.examples.map { ExampleState(it.id, it.title, it.summary) })
    }

/** A line that a swipe towards the start deletes, as on iOS. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun DeletableLine(enabled: Boolean, onDelete: () -> Unit, content: @Composable () -> Unit) {
    val state = rememberSwipeToDismissBoxState()
    SwipeToDismissBox(
        state = state,
        enableDismissFromStartToEnd = false,
        gesturesEnabled = enabled,
        onDismiss = { if (it == SwipeToDismissBoxValue.EndToStart) onDelete() },
        backgroundContent = {
            if (state.dismissDirection == SwipeToDismissBoxValue.EndToStart) {
                Box(
                    Modifier.fillMaxSize().background(MaterialTheme.colorScheme.errorContainer).padding(horizontal = 24.dp),
                    contentAlignment = Alignment.CenterEnd,
                ) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.onErrorContainer)
                }
            }
        },
    ) {
        // Opaque, so that the swipe background only shows where the line moved away.
        Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.background)) { content() }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 4.dp),
    )
}
