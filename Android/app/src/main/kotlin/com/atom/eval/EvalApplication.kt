package com.atom.eval

import android.app.Application
import android.content.Context
import com.atom.eval.data.SheetStore

class EvalApplication : Application() {
    /** The sheets of this device, opened once for the app. */
    lateinit var sheetStore: SheetStore
        private set

    override fun onCreate() {
        super.onCreate()
        // Sets up Foundation for the Swift engine and loads the native libraries
        // named by SKIP_BRIDGE_MODULES in the manifest (EvalBridge).
        skip.foundation.ProcessInfo.launch(applicationContext)
        sheetStore = SheetStore(this)
    }
}

/** The app's [SheetStore], from any context of the app. */
val Context.sheetStore: SheetStore
    get() = (applicationContext as EvalApplication).sheetStore
