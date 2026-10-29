package com.atom.eval

import android.app.Application

class EvalApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Sets up Foundation for the Swift engine and loads the native libraries
        // named by SKIP_BRIDGE_MODULES in the manifest (EvalBridge).
        skip.foundation.ProcessInfo.launch(applicationContext)
    }
}
