package com.atom.eval

import android.app.Application
import android.content.Context
import com.atom.eval.data.AppSettings
import com.atom.eval.data.SheetStore

class EvalApplication : Application() {
    /** The sheets of this device, opened once for the app. */
    lateinit var sheetStore: SheetStore
        private set

    /** The preferences of « Réglages ». */
    lateinit var settings: AppSettings
        private set

    override fun onCreate() {
        super.onCreate()
        // Sets up Foundation for the Swift engine and loads the native libraries
        // named by SKIP_BRIDGE_MODULES in the manifest (EvalBridge).
        skip.foundation.ProcessInfo.launch(applicationContext)
        settings = AppSettings(this)
        sheetStore = SheetStore(this)
    }
}

/** The app's [AppSettings], from any context of the app. */
val Context.appSettings: AppSettings
    get() = (applicationContext as EvalApplication).settings

/** The app's [SheetStore], from any context of the app. */
val Context.sheetStore: SheetStore
    get() = (applicationContext as EvalApplication).sheetStore
