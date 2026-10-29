package com.atom.eval.scanner

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.compose.CameraXViewfinder
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.SurfaceRequest
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.lifecycle.awaitInstance
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.FlashlightOff
import androidx.compose.material.icons.outlined.FlashlightOn
import androidx.compose.material.icons.outlined.PhotoLibrary
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import androidx.core.content.edit
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.atom.eval.R
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** The frame of what is read, centered: its share of the width and of the height of the view. */
private const val FRAME_WIDTH = 0.86f
private const val FRAME_HEIGHT = 0.3f

/**
 * « Scanner une formule » (iOS FormulaScannerView): the camera, or a photo of the
 * library, with a frame around what is read. The picture is read on the device and
 * is neither kept nor sent; the lines read go to [onLines].
 */
@Composable
fun FormulaScanner(declared: List<String>, onLines: (List<String>) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val preferences = remember { context.getSharedPreferences("settings", android.content.Context.MODE_PRIVATE) }
    // Without a model that reads the picture, fractions and exponents are often misread, as on iOS without Apple Intelligence.
    var warns by rememberSaveable { mutableStateOf(!preferences.getBoolean(WARNING_HIDDEN, false)) }
    if (warns) {
        ReadingWarning(
            onContinue = { hide ->
                if (hide) preferences.edit { putBoolean(WARNING_HIDDEN, true) }
                warns = false
            },
            onCancel = onDismiss,
        )
        return
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        ScannerContent(declared, onLines, onDismiss)
    }
}

@Composable
private fun ScannerContent(declared: List<String>, onLines: (List<String>) -> Unit, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val scope = rememberCoroutineScope()
    var hasPermission by remember {
        mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
    }
    var permissionDenied by remember { mutableStateOf(false) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        hasPermission = granted
        permissionDenied = !granted
    }
    var picked by remember { mutableStateOf<Bitmap?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
        uri?.let { picked = decode(context, it) }
    }
    var surfaceRequest by remember { mutableStateOf<SurfaceRequest?>(null) }
    val preview = remember { Preview.Builder().build() }
    val capture = remember { ImageCapture.Builder().build() }
    var camera by remember { mutableStateOf<Camera?>(null) }
    var noCamera by remember { mutableStateOf(false) }
    var torch by remember { mutableStateOf(false) }
    var zoom by remember { mutableStateOf(1f) }
    var frozen by remember { mutableStateOf<Bitmap?>(null) }
    var isReading by remember { mutableStateOf(false) }
    var failure by remember { mutableStateOf<String?>(null) }
    var viewSize by remember { mutableStateOf(IntSize.Zero) }
    val nothingRead = stringResource(R.string.scan_nothing_read)

    // The permission is asked the first time the scanner opens.
    LaunchedEffect(Unit) { if (!hasPermission) permission.launch(Manifest.permission.CAMERA) }
    LaunchedEffect(hasPermission, picked) {
        if (!hasPermission || picked != null) return@LaunchedEffect
        preview.setSurfaceProvider { surfaceRequest = it }
        val provider = ProcessCameraProvider.awaitInstance(context)
        try {
            camera = provider.bindToLifecycle(lifecycleOwner, CameraSelector.DEFAULT_BACK_CAMERA, preview, capture)
            awaitCancellation()
        } catch (_: IllegalArgumentException) {
            noCamera = true
        } finally {
            provider.unbindAll()
            camera = null
        }
    }

    /** Reads the part of `image` inside the frame, `image` being shown with `scale`. */
    fun read(image: Bitmap, scale: ContentScale) {
        frozen = image
        isReading = true
        scope.launch {
            val cropped = cropToFrame(image, viewSize, scale)
            val lines = runCatching { readFormulas(cropped, declared) }.getOrDefault(emptyList())
            isReading = false
            if (lines.isEmpty()) {
                frozen = null
                failure = nothingRead
            } else {
                onLines(lines)
            }
        }
    }

    fun shoot() {
        capture.takePicture(ContextCompat.getMainExecutor(context), object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                val bitmap = image.toBitmap().rotated(image.imageInfo.rotationDegrees)
                image.close()
                read(bitmap, ContentScale.Crop)
            }

            override fun onError(exception: ImageCaptureException) {
                failure = nothingRead
            }
        })
    }

    Box(
        Modifier
            .fillMaxSize()
            .background(Color.Black)
            .onSizeChanged { viewSize = it }
            .pointerInput(camera) {
                // A pinch zooms, up to ×6.
                detectTransformGestures { _, _, change, _ ->
                    val state = camera?.cameraInfo?.zoomState?.value ?: return@detectTransformGestures
                    zoom = (zoom * change).coerceIn(state.minZoomRatio, min(6f, state.maxZoomRatio))
                    camera?.cameraControl?.setZoomRatio(zoom)
                }
            },
    ) {
        val image = frozen ?: picked
        when {
            image != null -> Image(
                image.asImageBitmap(), contentDescription = null, modifier = Modifier.fillMaxSize(),
                contentScale = if (frozen != null && picked == null) ContentScale.Crop else ContentScale.Fit,
            )
            surfaceRequest != null && hasPermission && !noCamera -> CameraXViewfinder(surfaceRequest!!, Modifier.fillMaxSize())
        }
        FrameOverlay()

        Column(Modifier.fillMaxSize().safeDrawingPadding()) {
            Row(Modifier.fillMaxWidth().padding(8.dp)) {
                IconButton(onClick = onDismiss, colors = IconButtonDefaults.iconButtonColors(contentColor = Color.White)) {
                    Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.close))
                }
            }
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
                val message = when {
                    permissionDenied && picked == null -> stringResource(R.string.scan_camera_denied)
                    noCamera && picked == null -> stringResource(R.string.scan_no_camera)
                    else -> null
                }
                message?.let { Hint(it) }
                if (permissionDenied && picked == null) {
                    FilledTonalButton(
                        onClick = {
                            context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", context.packageName, null)))
                        },
                        modifier = Modifier.padding(top = 72.dp),
                    ) { Text(stringResource(R.string.open_settings)) }
                }
            }
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Hint(
                    when {
                        isReading -> stringResource(R.string.scan_reading)
                        picked != null -> stringResource(R.string.scan_hint_photo)
                        else -> stringResource(R.string.scan_hint_camera)
                    },
                    showsProgress = isReading,
                )
            }
            Row(
                Modifier.fillMaxWidth().padding(vertical = 24.dp),
                horizontalArrangement = Arrangement.SpaceEvenly,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RoundButton(
                    if (picked != null) Icons.Outlined.CameraAlt else Icons.Outlined.PhotoLibrary,
                    stringResource(if (picked != null) R.string.scan_back_to_camera else R.string.scan_choose_photo),
                ) {
                    if (picked != null) picked = null
                    else picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
                }
                // The shutter, or « Lire » on a photo.
                Box(
                    Modifier
                        .size(76.dp)
                        .border(4.dp, Color.White, CircleShape)
                        .padding(8.dp)
                        .background(Color.White, CircleShape)
                        .clickable(enabled = !isReading && (picked != null || camera != null), onClickLabel = stringResource(R.string.scan_shoot)) {
                            picked?.let { read(it, ContentScale.Fit) } ?: shoot()
                        },
                )
                val hasTorch = camera?.cameraInfo?.hasFlashUnit() == true && picked == null
                RoundButton(
                    if (torch) Icons.Outlined.FlashlightOn else Icons.Outlined.FlashlightOff,
                    stringResource(R.string.scan_torch),
                    enabled = hasTorch,
                ) {
                    torch = !torch
                    camera?.cameraControl?.enableTorch(torch)
                }
            }
        }
    }

    failure?.let { message ->
        AlertDialog(
            onDismissRequest = { failure = null },
            title = { Text(stringResource(R.string.scan_failed)) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { failure = null }) { Text(stringResource(R.string.ok)) } },
        )
    }
}

/** The outside of the frame is dimmed; white corners mark the frame, a cross its center. */
@Composable
private fun FrameOverlay() {
    Canvas(Modifier.fillMaxSize()) {
        val frame = frameRect(size)
        val hole = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(frame, CornerRadius(16.dp.toPx()))) }
        clipPath(hole, ClipOp.Difference) { drawRect(Color.Black.copy(alpha = 0.5f)) }
        val corner = 28.dp.toPx()
        val stroke = Stroke(4.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round)
        for ((x, y, dx, dy) in listOf(
            listOf(frame.left, frame.top, 1f, 1f), listOf(frame.right, frame.top, -1f, 1f),
            listOf(frame.left, frame.bottom, 1f, -1f), listOf(frame.right, frame.bottom, -1f, -1f),
        )) {
            val path = Path().apply {
                moveTo(x, y + dy * corner)
                lineTo(x, y)
                lineTo(x + dx * corner, y)
            }
            // A dark edge keeps the corners visible on a white page, as their shadow on iOS.
            drawPath(path, Color.Black.copy(alpha = 0.35f), style = Stroke(7.dp.toPx(), cap = androidx.compose.ui.graphics.StrokeCap.Round))
            drawPath(path, Color.White, style = stroke)
        }
        val center = frame.center
        val arm = 8.dp.toPx()
        drawLine(Color.White, Offset(center.x - arm, center.y), Offset(center.x + arm, center.y), 2.dp.toPx())
        drawLine(Color.White, Offset(center.x, center.y - arm), Offset(center.x, center.y + arm), 2.dp.toPx())
    }
}

private fun frameRect(size: Size): Rect {
    val width = size.width * FRAME_WIDTH
    val height = size.height * FRAME_HEIGHT
    return Rect(Offset((size.width - width) / 2, (size.height - height) / 2), Size(width, height))
}

/** The part of an image inside the frame, the image being drawn in the view with `scale`. */
private fun cropToFrame(image: Bitmap, view: IntSize, scale: ContentScale): Bitmap {
    if (view.width == 0 || view.height == 0) return image
    val factor = if (scale == ContentScale.Crop) max(view.width / image.width.toFloat(), view.height / image.height.toFloat())
    else min(view.width / image.width.toFloat(), view.height / image.height.toFloat())
    val dx = (view.width - image.width * factor) / 2
    val dy = (view.height - image.height * factor) / 2
    val frame = frameRect(Size(view.width.toFloat(), view.height.toFloat()))
    val left = ((frame.left - dx) / factor).roundToInt().coerceIn(0, image.width - 1)
    val top = ((frame.top - dy) / factor).roundToInt().coerceIn(0, image.height - 1)
    val right = ((frame.right - dx) / factor).roundToInt().coerceIn(left + 1, image.width)
    val bottom = ((frame.bottom - dy) / factor).roundToInt().coerceIn(top + 1, image.height)
    return Bitmap.createBitmap(image, left, top, right - left, bottom - top)
}

private fun Bitmap.rotated(degrees: Int): Bitmap =
    if (degrees == 0) this else Bitmap.createBitmap(this, 0, 0, width, height, Matrix().apply { postRotate(degrees.toFloat()) }, true)

/** A photo of the library, as a bitmap the text reader can read. */
private fun decode(context: android.content.Context, uri: Uri): Bitmap? = runCatching {
    ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.contentResolver, uri)) { decoder, _, _ ->
        decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
    }
}.getOrNull()

@Composable
private fun Hint(text: String, showsProgress: Boolean = false) {
    Surface(shape = CircleShape, color = Color.Black.copy(alpha = 0.55f), contentColor = Color.White) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            if (showsProgress) CircularProgressIndicator(Modifier.size(16.dp).padding(end = 0.dp), color = Color.White, strokeWidth = 2.dp)
            Text(text, style = MaterialTheme.typography.labelLarge, modifier = Modifier.padding(start = if (showsProgress) 8.dp else 0.dp))
        }
    }
}

@Composable
private fun RoundButton(icon: androidx.compose.ui.graphics.vector.ImageVector, label: String, enabled: Boolean = true, onClick: () -> Unit) {
    IconButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.size(56.dp).background(Color.White.copy(alpha = if (enabled) 0.18f else 0.06f), CircleShape),
        colors = IconButtonDefaults.iconButtonColors(contentColor = Color.White, disabledContentColor = Color.White.copy(alpha = 0.3f)),
    ) {
        Icon(icon, contentDescription = label)
    }
}

/** « Lecture moins fiable », before the scanner (iOS ReadingWarningView). */
@Composable
private fun ReadingWarning(onContinue: (hide: Boolean) -> Unit, onCancel: () -> Unit) {
    var hide by rememberSaveable { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(stringResource(R.string.scan_warning_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(stringResource(R.string.scan_warning_message))
                Row(Modifier.clickable { hide = !hide }, verticalAlignment = Alignment.CenterVertically) {
                    Checkbox(checked = hide, onCheckedChange = { hide = it })
                    Text(stringResource(R.string.scan_warning_hide))
                }
            }
        },
        confirmButton = { TextButton(onClick = { onContinue(hide) }) { Text(stringResource(R.string.scan_continue)) } },
        dismissButton = { TextButton(onClick = onCancel) { Text(stringResource(R.string.cancel)) } },
    )
}

private const val WARNING_HIDDEN = "eval.readingWarningHidden.v1"
