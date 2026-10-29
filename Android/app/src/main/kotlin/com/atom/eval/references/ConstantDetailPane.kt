package com.atom.eval.references

import android.content.ActivityNotFoundException
import android.content.Intent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.OpenInNew
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import com.atom.eval.R
import com.atom.eval.ui.BackButton

/**
 * Everything about one constant, as iOS ConstantDetailView: what it is, its value,
 * what to type for it, its other spellings, its nature and its source.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ConstantDetailPane(constant: ConstantDetailState, onClose: (() -> Unit)?) {
    val context = LocalContext.current
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(constant.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { onClose?.let { BackButton(it) } },
            )
        },
    ) { padding ->
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(padding),
        ) {
            Text(
                constant.detail,
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
            )
            // The value and the names can be selected and copied.
            SelectionContainer {
                Column {
                    DetailItem(
                        stringResource(R.string.constant_value),
                        constant.valueText,
                        Modifier.semantics { contentDescription = constant.spokenValue },
                    )
                    DetailItem(stringResource(R.string.constant_input), constant.id, monospaced = true)
                    if (constant.aliases.isNotEmpty()) {
                        DetailItem(stringResource(R.string.constant_aliases), constant.aliases.joinToString(", "), monospaced = true)
                    }
                }
            }
            DetailItem(stringResource(R.string.constant_nature), constant.natureTitle)
            val sourceUrl = constant.sourceUrl
            if (sourceUrl != null) {
                ListItem(
                    headlineContent = {
                        Text(
                            stringResource(R.string.constant_source_link, constant.sourceName),
                            color = MaterialTheme.colorScheme.primary,
                        )
                    },
                    trailingContent = { Icon(Icons.AutoMirrored.Outlined.OpenInNew, contentDescription = null) },
                    modifier = Modifier.clickable(role = Role.Button) {
                        try {
                            context.startActivity(Intent(Intent.ACTION_VIEW, sourceUrl.toUri()))
                        } catch (_: ActivityNotFoundException) {
                            // No browser on this device: the source stays named.
                        }
                    },
                )
            } else {
                DetailItem(stringResource(R.string.constant_source), constant.sourceName)
            }
        }
    }
}

@Composable
private fun DetailItem(label: String, value: String, modifier: Modifier = Modifier, monospaced: Boolean = false) {
    ListItem(
        overlineContent = { Text(label) },
        headlineContent = {
            Text(
                value,
                fontFamily = if (monospaced) FontFamily.Monospace else null,
                style = MaterialTheme.typography.bodyLarge.copy(fontFeatureSettings = "tnum"),
                modifier = modifier,
            )
        },
    )
}
