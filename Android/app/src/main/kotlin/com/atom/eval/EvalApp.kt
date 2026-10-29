package com.atom.eval

import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.filled.Functions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteItem
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.atom.eval.references.ReferenceScreen
import com.atom.eval.sheets.CalculationScreen

private enum class EvalTab { Calculation, References }

/** The two tabs of the app, as on iOS: a bottom bar on phones, a rail on larger screens. */
@Composable
fun EvalApp() {
    val store = LocalContext.current.sheetStore
    val storageProblem by store.storageProblem.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(EvalTab.Calculation) }
    // Each tab keeps its scroll positions and open panes while the other one shows.
    val tabStates = rememberSaveableStateHolder()

    NavigationSuiteScaffold(
        navigationItems = {
            NavigationSuiteItem(
                selected = tab == EvalTab.Calculation,
                onClick = { tab = EvalTab.Calculation },
                icon = { Icon(Icons.Filled.Functions, contentDescription = null) },
                label = { Text(stringResource(R.string.tab_calculation)) },
            )
            NavigationSuiteItem(
                selected = tab == EvalTab.References,
                onClick = { tab = EvalTab.References },
                icon = {
                    Icon(
                        if (tab == EvalTab.References) Icons.AutoMirrored.Filled.MenuBook
                        else Icons.AutoMirrored.Outlined.MenuBook,
                        contentDescription = null,
                    )
                },
                label = { Text(stringResource(R.string.tab_references)) },
            )
        },
    ) {
        tabStates.SaveableStateProvider(tab) {
            when (tab) {
                EvalTab.Calculation -> CalculationScreen()
                EvalTab.References -> ReferenceScreen()
            }
        }
    }

    storageProblem?.let { message ->
        AlertDialog(
            onDismissRequest = store::dismissStorageProblem,
            confirmButton = {
                TextButton(onClick = store::dismissStorageProblem) { Text(stringResource(R.string.ok)) }
            },
            title = { Text(stringResource(R.string.storage_problem_title)) },
            text = { Text(message) },
        )
    }
}
