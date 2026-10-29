package com.atom.eval

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.atom.eval.ui.theme.EvalTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            val accent by appSettings.accent.collectAsStateWithLifecycle()
            val warmBackground by appSettings.warmBackground.collectAsStateWithLifecycle()
            EvalTheme(accent = accent, warmBackground = warmBackground) {
                EvalApp()
            }
        }
    }

    override fun onStop() {
        super.onStop()
        // Edits reach the disk before the app may be stopped, as on iOS.
        sheetStore.flush()
    }
}
