package com.atom.eval

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import eval.bridge.LineResult
import eval.bridge.SheetEvaluator
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(colorScheme = if (isSystemInDarkTheme()) darkColorScheme() else lightColorScheme()) {
                SheetScreen()
            }
        }
    }
}

// A first sheet: the text on top, and below it each line the engine evaluates.
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SheetScreen() {
    val evaluator = remember { SheetEvaluator() }
    // One evaluation at a time, off the main thread, as on iOS.
    val engine = remember { Dispatchers.Default.limitedParallelism(1) }
    var source by rememberSaveable { mutableStateOf("E = 0,5 * m * v²\nm = 80 kg\nv = 5 m/s\nE =") }
    // The previous results stay on screen until the new ones are ready.
    val lines by produceState(emptyList<LineResult>(), source) {
        // Waits for typing to pause, except for the first evaluation.
        if (value.isNotEmpty()) delay(180)
        value = withContext(engine) { evaluator.evaluate(source) }
    }

    Scaffold(
        topBar = { TopAppBar(title = { Text(stringResource(R.string.app_name)) }) },
        // Includes the keyboard, so that the results stay above it.
        contentWindowInsets = WindowInsets.safeDrawing
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            OutlinedTextField(
                value = source,
                onValueChange = { source = it },
                modifier = Modifier.fillMaxWidth().padding(16.dp).weight(1f, fill = false),
                minLines = 4
            )
            LazyColumn(Modifier.weight(1f)) {
                items(lines, key = { it.index }) { line ->
                    ListItem(
                        headlineContent = { Text(line.source) },
                        supportingContent = line.message?.let { { Text(it) } },
                        trailingContent = line.value?.let { { Text(it, color = MaterialTheme.colorScheme.primary) } }
                    )
                }
            }
        }
    }
}
