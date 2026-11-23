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
import androidx.compose.material3.adaptive.currentWindowAdaptiveInfo
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffold
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteScaffoldDefaults
import androidx.compose.material3.adaptive.navigationsuite.NavigationSuiteType
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.isImeVisible
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.atom.eval.references.ReferenceScreen
import com.atom.eval.sheets.CalculationScreen
import kotlinx.coroutines.delay

private enum class EvalTab { Calculation, References }

/** The two tabs of the app, as on iOS: a bottom bar on phones, a rail on larger screens. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun EvalApp() {
    val store = LocalContext.current.sheetStore
    val storageProblem by store.storageProblem.collectAsStateWithLifecycle()
    val insertion by store.referenceInsertion.collectAsStateWithLifecycle()
    var tab by rememberSaveable { mutableStateOf(EvalTab.Calculation) }
    // « Ajouter à la feuille » in Références shows the Calcul tab and reads the addition aloud.
    val view = LocalView.current
    val context = LocalContext.current
    LaunchedEffect(insertion) {
        val added = insertion ?: return@LaunchedEffect
        tab = EvalTab.Calculation
        if (added.lineNumber > 0) {
            // A moment, so TalkBack is done with the Références tab.
            delay(600)
            view.announceForAccessibility(context.getString(R.string.added_to_sheet, added.lineNumber, added.name))
        }
        store.consumeReferenceInsertion()
    }
    // Each tab keeps its scroll positions and open panes while the other one shows.
    val tabStates = rememberSaveableStateHolder()
    val defaultType = NavigationSuiteScaffoldDefaults.navigationSuiteType(currentWindowAdaptiveInfo())
    // The bottom bar gives its room to the keyboard while a line is typed; a rail stays.
    val isBottomBar = defaultType == NavigationSuiteType.NavigationBar ||
        defaultType == NavigationSuiteType.ShortNavigationBarCompact ||
        defaultType == NavigationSuiteType.ShortNavigationBarMedium
    val navigationType = if (WindowInsets.isImeVisible && isBottomBar) {
        NavigationSuiteType.None
    } else defaultType

    NavigationSuiteScaffold(
        navigationSuiteType = navigationType,
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
