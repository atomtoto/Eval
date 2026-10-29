package com.atom.eval.sheets

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.LibraryBooks
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.DriveFileRenameOutline
import androidx.compose.material.icons.outlined.FileCopy
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Button
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import com.atom.eval.R
import com.atom.eval.help.HelpDialog
import com.atom.eval.settings.SettingsDialog
import com.atom.eval.ui.EmptyState
import com.atom.eval.ui.NoSearchResults
import com.atom.eval.ui.SearchField
import com.atom.eval.ui.relativeDate
import kotlinx.coroutines.delay

/** What can be done to a sheet of the list. */
class SheetRowActions(
    val open: (String) -> Unit,
    val rename: (SheetRowState) -> Unit,
    val duplicate: (String) -> Unit,
    val share: (String) -> Unit,
    val delete: (SheetRowState) -> Unit,
)

/**
 * The list pane of the Calcul tab, as iOS SheetListView: « Feuilles », a search over
 * titles and text, the sheets most recent first, and the buttons that create one.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SheetListPane(
    state: SheetListState,
    query: String,
    onQueryChange: (String) -> Unit,
    /** The sheet shown beside the list, highlighted; null when the list is alone. */
    selectedId: String?,
    snackbarHostState: SnackbarHostState,
    onCreate: () -> Unit,
    onShowExamples: () -> Unit,
    actions: SheetRowActions,
) {
    val listState = rememberLazyListState()
    // Relative dates move on every minute, and at once after a change.
    val now by produceState(System.currentTimeMillis(), state.rows) {
        while (true) {
            value = System.currentTimeMillis()
            delay(60_000)
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.sheets_title)) },
                actions = {
                    IconButton(onClick = onShowExamples) {
                        Icon(
                            Icons.AutoMirrored.Outlined.LibraryBooks,
                            contentDescription = stringResource(R.string.new_from_example),
                        )
                    }
                    var showsSettings by rememberSaveable { mutableStateOf(false) }
                    IconButton(onClick = { showsSettings = true }) {
                        Icon(Icons.Outlined.Settings, contentDescription = stringResource(R.string.settings))
                    }
                    if (showsSettings) SettingsDialog { showsSettings = false }
                    var showsHelp by rememberSaveable { mutableStateOf(false) }
                    IconButton(onClick = { showsHelp = true }) {
                        Icon(Icons.AutoMirrored.Outlined.HelpOutline, contentDescription = stringResource(R.string.help))
                    }
                    if (showsHelp) HelpDialog { showsHelp = false }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(
                text = { Text(stringResource(R.string.new_sheet)) },
                icon = { Icon(Icons.Filled.Add, contentDescription = null) },
                onClick = onCreate,
                // Shrinks to its icon once the list scrolls, to uncover the rows.
                expanded = !listState.canScrollBackward,
            )
        },
        snackbarHost = { SnackbarHost(snackbarHostState) },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            SearchField(
                query = query,
                onQueryChange = onQueryChange,
                placeholder = stringResource(R.string.search_sheets),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 8.dp),
            )
            when {
                state.isLibraryEmpty -> EmptyState(
                    icon = Icons.Outlined.Description,
                    title = stringResource(R.string.no_sheet),
                    message = stringResource(R.string.no_sheet_list_message),
                ) {
                    Button(onClick = onCreate) { Text(stringResource(R.string.new_sheet)) }
                }
                state.rows.isEmpty() -> NoSearchResults(query)
                else -> LazyColumn(
                    state = listState,
                    // Keeps the last row clear of the button.
                    contentPadding = PaddingValues(bottom = 88.dp),
                ) {
                    items(state.rows, key = { it.id }) { row ->
                        SheetRow(
                            row = row,
                            now = now,
                            isSelected = row.id == selectedId,
                            actions = actions,
                            modifier = Modifier.animateItem(),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun SheetRow(
    row: SheetRowState,
    now: Long,
    isSelected: Boolean,
    actions: SheetRowActions,
    modifier: Modifier = Modifier,
) {
    var showsMenu by remember { mutableStateOf(false) }
    val dismissState = rememberSwipeToDismissBoxState()
    val renameLabel = stringResource(R.string.rename)
    val duplicateLabel = stringResource(R.string.duplicate)
    val shareLabel = stringResource(R.string.share)
    val deleteLabel = stringResource(R.string.delete)

    // Swiping toward the start deletes, as on iOS; Annuler then brings the sheet back.
    SwipeToDismissBox(
        state = dismissState,
        backgroundContent = {
            if (dismissState.dismissDirection == SwipeToDismissBoxValue.EndToStart) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .background(MaterialTheme.colorScheme.error)
                        .padding(horizontal = 24.dp),
                    contentAlignment = Alignment.CenterEnd,
                ) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.onError)
                }
            }
        },
        modifier = modifier,
        enableDismissFromStartToEnd = false,
        onDismiss = { actions.delete(row) },
    ) {
        Box {
            ListItem(
                headlineContent = {
                    Text(row.title, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.titleMedium)
                },
                supportingContent = { SheetRowDetail(row, now) },
                colors = ListItemDefaults.colors(
                    containerColor = if (isSelected) MaterialTheme.colorScheme.secondaryContainer
                    else MaterialTheme.colorScheme.surface,
                ),
                modifier = Modifier
                    .combinedClickable(
                        onLongClickLabel = stringResource(R.string.sheet_actions),
                        onLongClick = { showsMenu = true },
                        onClick = { actions.open(row.id) },
                    )
                    // The menu's actions, reachable without the long press or the swipe.
                    .semantics {
                        customActions = listOf(
                            CustomAccessibilityAction(renameLabel) { actions.rename(row); true },
                            CustomAccessibilityAction(duplicateLabel) { actions.duplicate(row.id); true },
                            CustomAccessibilityAction(shareLabel) { actions.share(row.id); true },
                            CustomAccessibilityAction(deleteLabel) { actions.delete(row); true },
                        )
                    },
            )
            DropdownMenu(expanded = showsMenu, onDismissRequest = { showsMenu = false }) {
                DropdownMenuItem(
                    text = { Text(renameLabel) },
                    leadingIcon = { Icon(Icons.Outlined.DriveFileRenameOutline, contentDescription = null) },
                    onClick = { showsMenu = false; actions.rename(row) },
                )
                DropdownMenuItem(
                    text = { Text(duplicateLabel) },
                    leadingIcon = { Icon(Icons.Outlined.FileCopy, contentDescription = null) },
                    onClick = { showsMenu = false; actions.duplicate(row.id) },
                )
                DropdownMenuItem(
                    text = { Text(shareLabel) },
                    leadingIcon = { Icon(Icons.Outlined.Share, contentDescription = null) },
                    onClick = { showsMenu = false; actions.share(row.id) },
                )
                HorizontalDivider()
                DropdownMenuItem(
                    text = { Text(deleteLabel, color = MaterialTheme.colorScheme.error) },
                    leadingIcon = {
                        Icon(Icons.Outlined.Delete, contentDescription = null, tint = MaterialTheme.colorScheme.error)
                    },
                    onClick = { showsMenu = false; actions.delete(row) },
                )
            }
        }
    }
}

/** The date and the first result; at large text sizes they stack and nothing is cut short. */
@Composable
private fun SheetRowDetail(row: SheetRowState, now: Long) {
    val date = relativeDate(row.modifiedAt, now)
    val stacks = LocalDensity.current.fontScale >= 1.5f
    val preview: @Composable () -> Unit = {
        if (row.preview != null) {
            Text(
                row.preview,
                maxLines = if (stacks) Int.MAX_VALUE else 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.semantics { row.spokenPreview?.let { contentDescription = it } },
            )
        }
    }
    if (stacks) {
        Column {
            Text(date)
            preview()
        }
    } else {
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(date, maxLines = 1, softWrap = false)
            preview()
        }
    }
}
