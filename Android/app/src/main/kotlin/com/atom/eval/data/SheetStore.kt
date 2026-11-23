package com.atom.eval.data

import android.content.Context
import android.util.Log
import androidx.core.content.edit
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

/** A constant or unit of Références added to a sheet, announced and shown as on iOS. */
data class SheetInsertion(val sheetId: String, val lineNumber: Int, val name: String, val id: Long)

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
    private val appContext = context.applicationContext
    private val preferences = appContext.getSharedPreferences("app", Context.MODE_PRIVATE)
    private val _library = MutableStateFlow<SheetLibrary?>(null)
    private val _changes = MutableStateFlow(0L)
    private val _storageProblem = MutableStateFlow<String?>(null)
    private val _referenceInsertion = MutableStateFlow<SheetInsertion?>(null)
    private val _openSheetRequest = MutableStateFlow<String?>(null)
    private var pendingWrite: Job? = null

    /** Null while the sheets are read, a moment at launch. */
    val library: StateFlow<SheetLibrary?> = _library.asStateFlow()

    /** Counts the calls to [changed]: screens read the library again when it moves. */
    val changes: StateFlow<Long> = _changes.asStateFlow()

    /** The message of « Enregistrement impossible », when sheets can only live in memory. */
    val storageProblem: StateFlow<String?> = _storageProblem.asStateFlow()

    /** Set by « Ajouter à la feuille » in Références, read once by the app root. */
    val referenceInsertion: StateFlow<SheetInsertion?> = _referenceInsertion.asStateFlow()

    /** A sheet the Calcul tab opens, set by « Ajouter à la feuille » in Références. */
    val openSheetRequest: StateFlow<String?> = _openSheetRequest.asStateFlow()

    /** The sheet the app last showed, restored at the next launch as iOS @SceneStorage. */
    var lastOpenedSheetId: String?
        get() = preferences.getString(LAST_OPENED_SHEET, null)
        set(value) { preferences.edit { putString(LAST_OPENED_SHEET, value) } }

    init {
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

    /**
     * « Ajouter à la feuille », from Références: appends a line that asks for the value
     * of [symbol] to the sheet being shown, else the most recent one, else a new sheet,
     * as on iOS. The Calcul tab opens that sheet and the app announces the addition.
     */
    fun addReferenceToSheet(symbol: String, name: String) {
        val library = _library.value ?: return
        val target = library.mostRecentSheetId ?: library.createSheet()
        val editor = library.openEditor(target) ?: return
        val lineId = editor.appendFormula(symbol)
        changed()
        val lineNumber = lineId?.let { id -> editor.lines().indexOfFirst { it.id == id } + 1 } ?: 0
        _referenceInsertion.value = SheetInsertion(target, lineNumber, name, _changes.value)
        _openSheetRequest.value = target
    }

    /** Called once the app has shown the sheet and announced the insertion. */
    fun consumeReferenceInsertion() {
        _referenceInsertion.value = null
    }

    /** A write that has started finishes, even if a newer change cancels its job. */
    private suspend fun write(library: SheetLibrary) {
        val written = withContext(Dispatchers.IO + NonCancellable) { library.flush() }
        // iOS only logs a failed write: the next change tries again.
        if (!written) Log.w("Eval", "A sheet could not be written")
    }

    private companion object {
        const val LAST_OPENED_SHEET = "eval.selectedSheetID"
    }
}
