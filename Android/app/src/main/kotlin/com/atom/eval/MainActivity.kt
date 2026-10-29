package com.atom.eval

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.atom.eval.ui.theme.EvalTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            EvalTheme {
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
