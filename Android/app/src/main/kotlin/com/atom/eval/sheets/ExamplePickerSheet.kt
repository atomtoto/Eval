package com.atom.eval.sheets

import androidx.compose.foundation.clickable
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.atom.eval.R
import kotlinx.coroutines.launch

/**
 * « Nouvelle à partir d’un exemple »: the example sheets by domain. Choosing one
 * closes the sheet, then [onChoose] creates a new sheet from it.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExamplePickerSheet(
    categories: List<ExampleCategoryState>,
    onChoose: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val sheetState = rememberModalBottomSheetState()
    val scope = rememberCoroutineScope()

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = sheetState) {
        Text(
            stringResource(R.string.new_from_example),
            style = MaterialTheme.typography.titleLarge,
            modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 8.dp).semantics { heading() },
        )
        LazyColumn {
            for (category in categories) {
                item(key = "category-${category.id}") {
                    Text(
                        category.title,
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier
                            .padding(start = 24.dp, end = 24.dp, top = 16.dp, bottom = 4.dp)
                            .semantics { heading() },
                    )
                }
                items(category.examples, key = { "example-${it.id}" }) { example ->
                    ListItem(
                        headlineContent = { Text(example.title) },
                        supportingContent = { Text(example.summary) },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                        modifier = Modifier.clickable {
                            scope.launch { sheetState.hide() }.invokeOnCompletion { onChoose(example.id) }
                        },
                    )
                }
            }
        }
    }
}
