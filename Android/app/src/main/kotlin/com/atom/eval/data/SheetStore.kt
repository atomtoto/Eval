package com.atom.eval.data

import android.content.Context
import android.util.Log
import eval.bridge.SheetLibrary
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/**
 * The sheets of this device, opened once for the whole app. The library is read
 * from disk on [Dispatchers.IO] at launch, then used from the main thread only, as
 * the bridge requires; its files are written on [Dispatchers.IO].
 *
 * Compose cannot observe the Swift library: whoever changes it, through the library
 * or an editor, calls [changed], so that the screens read it again and the files
 * are written after a pause.
 */
class SheetStore(context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _library = MutableStateFlow<SheetLibrary?>(null)
    private val _changes = MutableStateFlow(0L)
    private val _storageProblem = MutableStateFlow<String?>(null)
    private var pendingWrite: Job? = null

    /** Null while the sheets are read, a moment at launch. */
    val library: StateFlow<SheetLibrary?> = _library.asStateFlow()

    /** Counts the calls to [changed]: screens read the library again when it moves. */
    val changes: StateFlow<Long> = _changes.asStateFlow()

    /** The message of « Enregistrement impossible », when sheets can only live in memory. */
    val storageProblem: StateFlow<String?> = _storageProblem.asStateFlow()

    init {
        val appContext = context.applicationContext
        scope.launch {
            val library = withContext(Dispatchers.IO) {
                SheetLibrary(File(appContext.filesDir, "Sheets").path)
            }
            _storageProblem.value = library.storageProblem
            _library.value = library
        }
    }

    /** The library, for screens shown once it is loaded, such as the Calcul tab. */
    fun requireLibrary(): SheetLibrary = checkNotNull(_library.value) { "The sheets are not loaded yet" }

    /**
     * Call on the main thread after any change made through the library or an
     * editor, an evaluation included: lists refresh, and pending files are written
     * [SheetLibrary.writeDelayMillis] after the last change.
     */
    fun changed() {
        _changes.update { it + 1 }
        val library = _library.value ?: return
        if (!library.hasPendingWrites) return
        pendingWrite?.cancel()
        pendingWrite = scope.launch {
            delay(SheetLibrary.writeDelayMillis)
            write(library)
        }
    }

    /** Writes the pending changes now, when the app leaves the foreground. */
    fun flush() {
        val library = _library.value ?: return
        pendingWrite?.cancel()
        pendingWrite = scope.launch { write(library) }
    }

    fun dismissStorageProblem() {
        _library.value?.dismissStorageProblem()
        _storageProblem.value = null
    }

    /** A write that has started finishes, even if a newer change cancels its job. */
    private suspend fun write(library: SheetLibrary) {
        val written = withContext(Dispatchers.IO + NonCancellable) { library.flush() }
        // iOS only logs a failed write: the next change tries again.
        if (!written) Log.w("Eval", "A sheet could not be written")
    }
}
