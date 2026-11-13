package com.introbird.pdfmakerflutter

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.ExifInterface
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private val channelName = "com.introbird.pdfmakerflutter/native_files"
    private val mainHandler = Handler(Looper.getMainLooper())
    private val workerPool = Executors.newFixedThreadPool(
        Runtime.getRuntime().availableProcessors().coerceIn(2, 4)
    )

    private val REQUEST_CODE_PICK_DIRECTORY = 4289
    private var pendingDirectoryResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDirectory" -> {
                        pendingDirectoryResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                            )
                        }
                        startActivityForResult(intent, REQUEST_CODE_PICK_DIRECTORY)
                    }

                    "openPdf" -> {
                        val filePath = call.argument<String>("path")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "File path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val contentUri: Uri = if (filePath.startsWith("content://")) {
                                Uri.parse(filePath)
                            } else {
                                val file = File(filePath)
                                if (!file.exists()) {
                                    result.error("FILE_NOT_FOUND", "PDF file does not exist: $filePath", null)
                                    return@setMethodCallHandler
                                }
                                val authority = "${applicationContext.packageName}.fileprovider"
                                FileProvider.getUriForFile(this, authority, file)
                            }

                            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(contentUri, "application/pdf")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            startActivity(viewIntent)
                            result.success(true)
                        } catch (e: ActivityNotFoundException) {
                            result.error("NO_VIEWER", "No PDF viewer app installed on this device.", null)
                        } catch (e: Exception) {
                            result.error("OPEN_ERROR", e.localizedMessage ?: "Failed to open PDF", null)
                        }
                    }

                    "deletePdf" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing path", null)
                            return@setMethodCallHandler
                        }
                        workerPool.execute {
                            try {
                                var deleted = false
                                if (path.startsWith("content://")) {
                                    val uri = Uri.parse(path)
                                    try {
                                        val doc = DocumentFile.fromSingleUri(applicationContext, uri)
                                        if (doc != null && doc.exists()) {
                                            deleted = doc.delete()
                                        }
                                    } catch (_: Exception) {}
                                    if (!deleted) {
                                        try {
                                            val count = applicationContext.contentResolver.delete(uri, null, null)
                                            deleted = count > 0
                                        } catch (_: Exception) {}
                                    }
                                } else {
                                    val f = File(path)
                                    if (f.exists()) {
                                        deleted = f.delete()
                                    }
                                    try {
                                        applicationContext.contentResolver.delete(
                                            MediaStore.Files.getContentUri("external"),
                                            "${MediaStore.Files.FileColumns.DATA} = ?",
                                            arrayOf(path)
                                        )
                                    } catch (_: Exception) {}
                                }
                                mainHandler.post { result.success(deleted) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("DELETE_ERROR", e.localizedMessage ?: "Failed to delete PDF", null) }
                            }
                        }
                    }

                    "readPdfBytes" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing path", null)
                            return@setMethodCallHandler
                        }
                        workerPool.execute {
                            try {
                                val bytes: ByteArray? = if (path.startsWith("content://")) {
                                    applicationContext.contentResolver.openInputStream(Uri.parse(path))?.use { it.readBytes() }
                                } else {
                                    val f = File(path)
                                    if (f.exists()) f.readBytes() else null
                                }
                                if (bytes != null) {
                                    mainHandler.post { result.success(bytes) }
                                } else {
                                    mainHandler.post { result.error("READ_ERROR", "Could not read bytes for: $path", null) }
                                }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("READ_ERROR", e.localizedMessage ?: "Failed to read PDF bytes", null) }
                            }
                        }
                    }

                    "getShareableFilePath" -> {
                        val path = call.argument<String>("path")
                        val fileName = call.argument<String>("fileName") ?: "document.pdf"
                        if (path.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing path", null)
                            return@setMethodCallHandler
                        }
                        workerPool.execute {
                            try {
                                if (path.startsWith("content://")) {
                                    val cacheFile = File(cacheDir, "share_${System.currentTimeMillis()}_$fileName")
                                    applicationContext.contentResolver.openInputStream(Uri.parse(path))?.use { input ->
                                        FileOutputStream(cacheFile).use { output ->
                                            input.copyTo(output)
                                        }
                                    }
                                    mainHandler.post { result.success(cacheFile.absolutePath) }
                                } else {
                                    mainHandler.post { result.success(path) }
                                }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("SHARE_ERROR", e.localizedMessage ?: "Failed to prepare share file", null) }
                            }
                        }
                    }

                    "savePdf" -> {
                        val fileName = call.argument<String>("fileName")
                        val bytes = call.argument<ByteArray>("bytes")
                        val folderUri = call.argument<String>("folderUri")
                        if (fileName.isNullOrBlank() || bytes == null) {
                            result.error("INVALID_ARGS", "Missing fileName or bytes", null)
                            return@setMethodCallHandler
                        }
                        workerPool.execute {
                            try {
                                // 1. Custom SAF Directory (if folderUri is set)
                                if (!folderUri.isNullOrBlank()) {
                                    val treeUri = Uri.parse(folderUri)
                                    val pickedDir = DocumentFile.fromTreeUri(applicationContext, treeUri)
                                        ?: throw IllegalStateException("Cannot access custom directory URI: $folderUri")

                                    val existing = pickedDir.findFile(fileName)
                                    if (existing != null && existing.exists()) {
                                        existing.delete()
                                    }
                                    val newFile = pickedDir.createFile("application/pdf", fileName)
                                        ?: throw IllegalStateException("Failed to create file in custom folder")

                                    applicationContext.contentResolver.openOutputStream(newFile.uri)?.use { os ->
                                        os.write(bytes)
                                        os.flush()
                                    }

                                    mainHandler.post {
                                        result.success(hashMapOf(
                                            "path" to newFile.uri.toString(),
                                            "uri" to newFile.uri.toString(),
                                            "fileName" to fileName,
                                            "isContentUri" to true
                                        ))
                                    }
                                    return@execute
                                }

                                // 2. Default Public Documents/PDF Maker directory
                                val savedPath = saveToPublicDocuments(fileName, bytes)
                                mainHandler.post {
                                    result.success(hashMapOf(
                                        "path" to savedPath,
                                        "uri" to savedPath,
                                        "fileName" to fileName,
                                        "isContentUri" to savedPath.startsWith("content://")
                                    ))
                                }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("SAVE_ERROR", e.localizedMessage ?: "Failed to save PDF", null)
                                }
                            }
                        }
                    }

                    "savePdfToPublicDocuments" -> {
                        val fileName = call.argument<String>("fileName")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (fileName.isNullOrBlank() || bytes == null) {
                            result.error("INVALID_ARGS", "Missing fileName or bytes", null)
                            return@setMethodCallHandler
                        }
                        workerPool.execute {
                            try {
                                val savedPath = saveToPublicDocuments(fileName, bytes)
                                mainHandler.post { result.success(savedPath) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("SAVE_ERROR", e.localizedMessage ?: "Failed to save PDF", null)
                                }
                            }
                        }
                    }

                    "listPdfs" -> {
                        val folderUri = call.argument<String>("folderUri")
                        workerPool.execute {
                            try {
                                val list = mutableListOf<Map<String, Any>>()
                                val seenKeys = mutableSetOf<String>()

                                // 1. If custom SAF folderUri provided, query DocumentFile
                                if (!folderUri.isNullOrBlank()) {
                                    try {
                                        val treeUri = Uri.parse(folderUri)
                                        val pickedDir = DocumentFile.fromTreeUri(applicationContext, treeUri)
                                        if (pickedDir != null && pickedDir.exists() && pickedDir.isDirectory) {
                                            for (doc in pickedDir.listFiles()) {
                                                val name = doc.name ?: continue
                                                if (name.endsWith(".pdf", ignoreCase = true)) {
                                                    val key = doc.uri.toString()
                                                    if (seenKeys.add(key)) {
                                                        list.add(mapOf(
                                                            "path" to doc.uri.toString(),
                                                            "uri" to doc.uri.toString(),
                                                            "name" to name,
                                                            "sizeBytes" to doc.length(),
                                                            "modified" to doc.lastModified(),
                                                            "isContentUri" to true
                                                        ))
                                                    }
                                                }
                                            }
                                        }
                                    } catch (e: Exception) {
                                        // Ignore and continue
                                    }
                                } else {
                                    // 2. Default folder: Documents/PDF Maker (+ legacy folders)
                                    // First: MediaStore query (Android 10+ compliant, finds all PDFs in Documents/PDF Maker)
                                    try {
                                        val queryUri = MediaStore.Files.getContentUri("external")
                                        val projection = arrayOf(
                                            MediaStore.Files.FileColumns._ID,
                                            MediaStore.Files.FileColumns.DISPLAY_NAME,
                                            MediaStore.Files.FileColumns.SIZE,
                                            MediaStore.Files.FileColumns.DATE_MODIFIED,
                                            MediaStore.Files.FileColumns.DATA
                                        )
                                        val selection = "(${MediaStore.Files.FileColumns.MIME_TYPE} = ? OR ${MediaStore.Files.FileColumns.DISPLAY_NAME} LIKE '%.pdf') AND " +
                                            "(${MediaStore.Files.FileColumns.DATA} LIKE '%/Documents/PDF Maker/%' OR " +
                                            "${MediaStore.Files.FileColumns.DATA} LIKE '%/Documents/PDF Maker Pro/%' OR " +
                                            "${MediaStore.Files.FileColumns.DATA} LIKE '%/Documents/PDF documents(pdf_maker)/%' OR " +
                                            "${MediaStore.Files.FileColumns.RELATIVE_PATH} LIKE 'Documents/PDF Maker%' OR " +
                                            "${MediaStore.Files.FileColumns.RELATIVE_PATH} LIKE 'Documents/PDF Maker Pro%')"
                                        val selectionArgs = arrayOf("application/pdf")

                                        applicationContext.contentResolver.query(
                                            queryUri,
                                            projection,
                                            selection,
                                            selectionArgs,
                                            "${MediaStore.Files.FileColumns.DATE_MODIFIED} DESC"
                                        )?.use { cursor ->
                                            val idCol = cursor.getColumnIndex(MediaStore.Files.FileColumns._ID)
                                            val nameCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.DISPLAY_NAME)
                                            val sizeCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.SIZE)
                                            val modCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATE_MODIFIED)
                                            val dataCol = cursor.getColumnIndex(MediaStore.Files.FileColumns.DATA)

                                            while (cursor.moveToNext()) {
                                                val id = if (idCol >= 0) cursor.getLong(idCol) else -1
                                                val name = if (nameCol >= 0) cursor.getString(nameCol) else null
                                                val size = if (sizeCol >= 0) cursor.getLong(sizeCol) else 0L
                                                val modSec = if (modCol >= 0) cursor.getLong(modCol) else 0L
                                                val dataPath = if (dataCol >= 0) cursor.getString(dataCol) else null

                                                val displayName = name ?: (dataPath?.let { File(it).name } ?: "PDF_${id}.pdf")
                                                if (!displayName.endsWith(".pdf", ignoreCase = true)) continue

                                                val contentUri = if (id >= 0) {
                                                    ContentUris.withAppendedId(queryUri, id).toString()
                                                } else null

                                                val filePath = dataPath ?: contentUri ?: ""
                                                val key = displayName.lowercase()
                                                if (seenKeys.add(key)) {
                                                    list.add(mapOf(
                                                        "path" to filePath,
                                                        "uri" to (contentUri ?: filePath),
                                                        "name" to displayName,
                                                        "sizeBytes" to size,
                                                        "modified" to (modSec * 1000L),
                                                        "isContentUri" to filePath.startsWith("content://")
                                                    ))
                                                }
                                            }
                                        }
                                    } catch (e: Exception) {
                                        // Ignore and continue
                                    }

                                    // Second: Direct filesystem scan of known paths
                                    val dirsToScan = mutableListOf<File>()
                                    val publicDocs = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
                                    dirsToScan.add(File(publicDocs, "PDF Maker"))
                                    dirsToScan.add(File(publicDocs, "PDF Maker Pro"))
                                    dirsToScan.add(File(publicDocs, "PDF documents(pdf_maker)"))

                                    // App-specific external & internal documents
                                    try {
                                        applicationContext.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)?.let {
                                            dirsToScan.add(File(it, "PDF Maker"))
                                            dirsToScan.add(it)
                                        }
                                        dirsToScan.add(File(applicationContext.filesDir, "PDF Maker"))
                                    } catch (_: Exception) {}

                                    for (d in dirsToScan) {
                                        try {
                                            if (d.exists() && d.isDirectory) {
                                                val files = d.listFiles() ?: continue
                                                for (f in files) {
                                                    if (f.isFile && f.name.endsWith(".pdf", ignoreCase = true)) {
                                                        val key = f.name.lowercase()
                                                        if (seenKeys.add(key)) {
                                                            list.add(mapOf(
                                                                "path" to f.absolutePath,
                                                                "uri" to f.absolutePath,
                                                                "name" to f.name,
                                                                "sizeBytes" to f.length(),
                                                                "modified" to f.lastModified(),
                                                                "isContentUri" to false
                                                            ))
                                                        }
                                                    }
                                                }
                                            }
                                        } catch (_: Exception) {}
                                    }
                                }

                                // Sort by modified date descending
                                list.sortByDescending { (it["modified"] as? Long) ?: 0L }

                                mainHandler.post { result.success(list) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("LIST_ERROR", e.localizedMessage ?: "Failed to list PDFs", null) }
                            }
                        }
                    }

                    "exportPdfToDownloads" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val fileName = call.argument<String>("fileName")
                        if (sourcePath.isNullOrBlank() || fileName.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing sourcePath or fileName", null)
                            return@setMethodCallHandler
                        }
                        workerPool.execute {
                            try {
                                val exportedPath = exportFileToPublicDownloads(sourcePath, fileName)
                                mainHandler.post { result.success(exportedPath) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("EXPORT_ERROR", e.localizedMessage ?: "Failed to export PDF", null)
                                }
                            }
                        }
                    }

                    "generateThumbnail" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val outPath = call.argument<String>("outPath")
                        val maxDim = call.argument<Int>("maxDimension") ?: 960
                        if (sourcePath.isNullOrBlank() || outPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing sourcePath or outPath", null)
                            return@setMethodCallHandler
                        }
                        workerPool.execute {
                            try {
                                val bitmap = decodeExifNormalizedBitmap(sourcePath, maxDim)
                                if (bitmap == null) {
                                    mainHandler.post { result.success(sourcePath) }
                                    return@execute
                                }
                                val scaled = scaleBitmapDown(bitmap, maxDim)
                                if (scaled !== bitmap) bitmap.recycle()

                                FileOutputStream(File(outPath)).use { fos ->
                                    scaled.compress(Bitmap.CompressFormat.JPEG, 84, fos)
                                    fos.flush()
                                }
                                scaled.recycle()
                                mainHandler.post { result.success(outPath) }
                            } catch (e: Exception) {
                                mainHandler.post { result.success(sourcePath) }
                            }
                        }
                    }

                    "loadEditPreview" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val basePreviewPath = call.argument<String>("basePreviewPath")
                        val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0
                        val maxDim = call.argument<Int>("maxDimension") ?: 960

                        if (sourcePath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing sourcePath", null)
                            return@setMethodCallHandler
                        }

                        workerPool.execute {
                            try {
                                val useExistingBase = !basePreviewPath.isNullOrBlank() &&
                                    basePreviewPath != sourcePath &&
                                    File(basePreviewPath).exists()

                                val normRot = ((rotationDegrees % 360) + 360) % 360

                                if (useExistingBase && normRot == 0) {
                                    val baseFile = File(basePreviewPath!!)
                                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                                    BitmapFactory.decodeFile(baseFile.absolutePath, bounds)
                                    if (bounds.outWidth > 0 && bounds.outHeight > 0) {
                                        val rawBytes = baseFile.readBytes()
                                        val payload = hashMapOf<String, Any>(
                                            "baseBytes" to rawBytes,
                                            "displayBytes" to rawBytes,
                                            "width" to bounds.outWidth,
                                            "height" to bounds.outHeight
                                        )
                                        mainHandler.post { result.success(payload) }
                                        return@execute
                                    }
                                }

                                val inputPath = if (useExistingBase) basePreviewPath!! else sourcePath
                                val decoded = decodeExifNormalizedBitmap(inputPath, maxDim)
                                if (decoded == null) {
                                    mainHandler.post { result.success(null) }
                                    return@execute
                                }
                                val baseBitmap = scaleBitmapDown(decoded, maxDim)
                                if (baseBitmap !== decoded) decoded.recycle()

                                val baseBytes: ByteArray = if (useExistingBase) {
                                    File(basePreviewPath!!).readBytes()
                                } else {
                                    val baos = ByteArrayOutputStream(baseBitmap.width * baseBitmap.height / 4)
                                    baseBitmap.compress(Bitmap.CompressFormat.JPEG, 85, baos)
                                    baos.toByteArray()
                                }

                                if (normRot == 0) {
                                    val w = baseBitmap.width
                                    val h = baseBitmap.height
                                    baseBitmap.recycle()
                                    val payload = hashMapOf<String, Any>(
                                        "baseBytes" to baseBytes,
                                        "displayBytes" to baseBytes,
                                        "width" to w,
                                        "height" to h
                                    )
                                    mainHandler.post { result.success(payload) }
                                } else {
                                    val rotated = rotateBitmap(baseBitmap, normRot)
                                    if (rotated !== baseBitmap) baseBitmap.recycle()
                                    val w = rotated.width
                                    val h = rotated.height
                                    val rotBaos = ByteArrayOutputStream(w * h / 4)
                                    rotated.compress(Bitmap.CompressFormat.JPEG, 85, rotBaos)
                                    rotated.recycle()
                                    val payload = hashMapOf<String, Any>(
                                        "baseBytes" to baseBytes,
                                        "displayBytes" to rotBaos.toByteArray(),
                                        "width" to w,
                                        "height" to h
                                    )
                                    mainHandler.post { result.success(payload) }
                                }
                            } catch (e: Exception) {
                                mainHandler.post { result.success(null) }
                            }
                        }
                    }

                    "rotatePreview" -> {
                        val baseBytes = call.argument<ByteArray>("baseBytes")
                        val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0
                        if (baseBytes == null) {
                            result.error("INVALID_ARGS", "Missing baseBytes", null)
                            return@setMethodCallHandler
                        }
                        workerPool.execute {
                            try {
                                val normRot = ((rotationDegrees % 360) + 360) % 360
                                if (normRot == 0) {
                                    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                                    BitmapFactory.decodeByteArray(baseBytes, 0, baseBytes.size, bounds)
                                    val payload = hashMapOf<String, Any>(
                                        "baseBytes" to baseBytes,
                                        "displayBytes" to baseBytes,
                                        "width" to bounds.outWidth.coerceAtLeast(1),
                                        "height" to bounds.outHeight.coerceAtLeast(1)
                                    )
                                    mainHandler.post { result.success(payload) }
                                    return@execute
                                }

                                val decoded = BitmapFactory.decodeByteArray(baseBytes, 0, baseBytes.size)
                                if (decoded == null) {
                                    mainHandler.post { result.success(null) }
                                    return@execute
                                }
                                val rotated = rotateBitmap(decoded, normRot)
                                if (rotated !== decoded) decoded.recycle()
                                val w = rotated.width
                                val h = rotated.height
                                val baos = ByteArrayOutputStream(w * h / 4)
                                rotated.compress(Bitmap.CompressFormat.JPEG, 85, baos)
                                rotated.recycle()

                                val payload = hashMapOf<String, Any>(
                                    "baseBytes" to baseBytes,
                                    "displayBytes" to baos.toByteArray(),
                                    "width" to w,
                                    "height" to h
                                )
                                mainHandler.post { result.success(payload) }
                            } catch (e: Exception) {
                                mainHandler.post { result.success(null) }
                            }
                        }
                    }

                    "cropAndRotatePreview" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val basePreviewPath = call.argument<String>("basePreviewPath")
                        val outPath = call.argument<String>("outPath")
                        val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0
                        val quadList = call.argument<List<Double>>("cropQuad")
                        val maxDim = call.argument<Int>("maxDimension") ?: 960

                        if (sourcePath.isNullOrBlank() || outPath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing paths", null)
                            return@setMethodCallHandler
                        }

                        workerPool.execute {
                            try {
                                val hasCustomCrop = quadList != null && quadList.size == 8
                                val inputPath = if (!hasCustomCrop &&
                                    !basePreviewPath.isNullOrBlank() &&
                                    basePreviewPath != sourcePath &&
                                    File(basePreviewPath).exists()
                                ) {
                                    basePreviewPath
                                } else {
                                    sourcePath
                                }

                                val decodeTargetDim = if (hasCustomCrop) 1600 else maxDim
                                var working = decodeExifNormalizedBitmap(inputPath, decodeTargetDim)
                                if (working == null) {
                                    mainHandler.post { result.success(basePreviewPath ?: sourcePath) }
                                    return@execute
                                }

                                val normRot = ((rotationDegrees % 360) + 360) % 360
                                if (normRot != 0) {
                                    val rotated = rotateBitmap(working, normRot)
                                    if (rotated !== working) working.recycle()
                                    working = rotated
                                }

                                if (hasCustomCrop && quadList != null) {
                                    val warped = perspectiveCropBitmap(working, quadList)
                                    if (warped !== working) working.recycle()
                                    working = warped
                                }

                                val finalPreview = scaleBitmapDown(working, maxDim)
                                if (finalPreview !== working) working.recycle()

                                FileOutputStream(File(outPath)).use { fos ->
                                    finalPreview.compress(Bitmap.CompressFormat.JPEG, 85, fos)
                                    fos.flush()
                                }
                                finalPreview.recycle()
                                mainHandler.post { result.success(outPath) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("CROP_ERROR", e.localizedMessage ?: "Failed to crop preview", null)
                                }
                            }
                        }
                    }

                    "processPageForPdf" -> {
                        val sourcePath = call.argument<String>("sourcePath")
                        val fallbackPath = call.argument<String>("fallbackPreviewPath")
                        val rotationDegrees = call.argument<Int>("rotationDegrees") ?: 0
                        val quadList = call.argument<List<Double>>("cropQuad")
                        val maxDim = call.argument<Int>("maxDimension") ?: 1800
                        val quality = call.argument<Int>("quality") ?: 70

                        val nextSourcePath = call.argument<String>("nextSourcePath")
                        val nextFallbackPath = call.argument<String>("nextFallbackPreviewPath")
                        val nextRotationDegrees = call.argument<Int>("nextRotationDegrees") ?: 0
                        val nextQuadList = call.argument<List<Double>>("nextCropQuad")

                        if (sourcePath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "Missing sourcePath", null)
                            return@setMethodCallHandler
                        }

                        workerPool.execute {
                            try {
                                var pageBitmap = processSinglePageBitmap(
                                    sourcePath = sourcePath,
                                    fallbackPath = fallbackPath,
                                    rotationDegrees = rotationDegrees,
                                    quadList = quadList,
                                    targetDecodeDim = if (quadList != null) max(maxDim, 2200) else maxDim
                                )
                                if (pageBitmap == null) {
                                    mainHandler.post { result.success(null) }
                                    return@execute
                                }

                                if (!nextSourcePath.isNullOrBlank()) {
                                    val nextBitmap = processSinglePageBitmap(
                                        sourcePath = nextSourcePath,
                                        fallbackPath = nextFallbackPath,
                                        rotationDegrees = nextRotationDegrees,
                                        quadList = nextQuadList,
                                        targetDecodeDim = if (nextQuadList != null) max(maxDim, 2200) else maxDim
                                    )
                                    if (nextBitmap != null) {
                                        val stitched = stitchBitmapsVertically(pageBitmap, nextBitmap)
                                        if (stitched !== pageBitmap) pageBitmap.recycle()
                                        nextBitmap.recycle()
                                        pageBitmap = stitched
                                    }
                                }

                                val resized = scaleBitmapDown(pageBitmap, maxDim)
                                if (resized !== pageBitmap) pageBitmap.recycle()

                                val outWidth = resized.width
                                val outHeight = resized.height
                                val baos = ByteArrayOutputStream(outWidth * outHeight / 4)
                                resized.compress(Bitmap.CompressFormat.JPEG, quality.coerceIn(40, 95), baos)
                                resized.recycle()

                                val payload = hashMapOf<String, Any>(
                                    "bytes" to baos.toByteArray(),
                                    "width" to outWidth.toDouble(),
                                    "height" to outHeight.toDouble()
                                )
                                mainHandler.post { result.success(payload) }
                            } catch (e: Exception) {
                                mainHandler.post {
                                    result.error("PROCESS_ERROR", e.localizedMessage ?: "Page processing error", null)
                                }
                            }
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_PICK_DIRECTORY) {
            val res = pendingDirectoryResult
            pendingDirectoryResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val treeUri = data.data!!
                try {
                    val takeFlags = (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
                    contentResolver.takePersistableUriPermission(treeUri, takeFlags)
                } catch (_: Exception) {}

                val docFile = DocumentFile.fromTreeUri(applicationContext, treeUri)
                val displayPath = formatTreeUriDisplayPath(treeUri, docFile?.name)
                res?.success(mapOf(
                    "uri" to treeUri.toString(),
                    "displayPath" to displayPath
                ))
            } else {
                res?.success(null)
            }
        }
    }

    private fun formatTreeUriDisplayPath(uri: Uri, docName: String?): String {
        try {
            val docId = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                DocumentsContract.getTreeDocumentId(uri)
            } else {
                uri.lastPathSegment ?: ""
            }
            val decoded = Uri.decode(docId)
            if (decoded.startsWith("primary:")) {
                val subPath = decoded.substringAfter("primary:").trim('/')
                return if (subPath.isEmpty()) "Documents/PDF Maker" else subPath
            } else if (decoded.contains(":")) {
                val parts = decoded.split(":", limit = 2)
                val sub = parts[1].trim('/')
                return if (sub.isEmpty()) "SD Card" else "SD Card/$sub"
            }
        } catch (_: Exception) {}
        return docName ?: "Documents/PDF Maker"
    }

    private fun processSinglePageBitmap(
        sourcePath: String,
        fallbackPath: String?,
        rotationDegrees: Int,
        quadList: List<Double>?,
        targetDecodeDim: Int
    ): Bitmap? {
        var bitmap = decodeExifNormalizedBitmap(sourcePath, targetDecodeDim)
        if (bitmap == null && !fallbackPath.isNullOrBlank()) {
            bitmap = decodeExifNormalizedBitmap(fallbackPath, targetDecodeDim)
        }
        if (bitmap == null) return null

        val normRot = ((rotationDegrees % 360) + 360) % 360
        if (normRot != 0) {
            val rotated = rotateBitmap(bitmap, normRot)
            if (rotated !== bitmap) bitmap.recycle()
            bitmap = rotated
        }

        if (quadList != null && quadList.size == 8) {
            val warped = perspectiveCropBitmap(bitmap, quadList)
            if (warped !== bitmap) bitmap.recycle()
            bitmap = warped
        }

        return bitmap
    }

    private fun decodeExifNormalizedBitmap(filePath: String, maxDimension: Int): Bitmap? {
        val file = File(filePath)
        if (!file.exists()) return null

        val boundsOpts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(filePath, boundsOpts)
        val rawW = boundsOpts.outWidth
        val rawH = boundsOpts.outHeight
        if (rawW <= 0 || rawH <= 0) return null

        var sampleSize = 1
        val longestSide = max(rawW, rawH)
        while (longestSide / (sampleSize * 2) >= maxDimension) {
            sampleSize *= 2
        }

        val decodeOpts = BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        val decoded = BitmapFactory.decodeFile(filePath, decodeOpts) ?: return null

        val exifMatrix = Matrix()
        try {
            val exif = ExifInterface(filePath)
            when (exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> exifMatrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> exifMatrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> exifMatrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> exifMatrix.preScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> exifMatrix.preScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> {
                    exifMatrix.preScale(-1f, 1f)
                    exifMatrix.postRotate(90f)
                }
                ExifInterface.ORIENTATION_TRANSVERSE -> {
                    exifMatrix.preScale(-1f, 1f)
                    exifMatrix.postRotate(270f)
                }
            }
        } catch (_: Exception) {}

        if (exifMatrix.isIdentity) {
            return decoded
        }

        val oriented = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, exifMatrix, true)
        if (oriented !== decoded) decoded.recycle()
        return oriented
    }

    private fun rotateBitmap(input: Bitmap, degrees: Int): Bitmap {
        val norm = ((degrees % 360) + 360) % 360
        if (norm == 0) return input
        val matrix = Matrix().apply { postRotate(norm.toFloat()) }
        return Bitmap.createBitmap(input, 0, 0, input.width, input.height, matrix, true)
    }

    private fun perspectiveCropBitmap(input: Bitmap, quad: List<Double>): Bitmap {
        val w = input.width
        val h = input.height
        if (w <= 2 || h <= 2 || quad.size < 8) return input

        val tlX = (quad[0] * w).toFloat().coerceIn(0f, (w - 1).toFloat())
        val tlY = (quad[1] * h).toFloat().coerceIn(0f, (h - 1).toFloat())
        val trX = (quad[2] * w).toFloat().coerceIn(0f, (w - 1).toFloat())
        val trY = (quad[3] * h).toFloat().coerceIn(0f, (h - 1).toFloat())
        val brX = (quad[4] * w).toFloat().coerceIn(0f, (w - 1).toFloat())
        val brY = (quad[5] * h).toFloat().coerceIn(0f, (h - 1).toFloat())
        val blX = (quad[6] * w).toFloat().coerceIn(0f, (w - 1).toFloat())
        val blY = (quad[7] * h).toFloat().coerceIn(0f, (h - 1).toFloat())

        if (quad[0] <= 0.005 && quad[1] <= 0.005 &&
            quad[2] >= 0.995 && quad[3] <= 0.005 &&
            quad[4] >= 0.995 && quad[5] >= 0.995 &&
            quad[6] <= 0.005 && quad[7] >= 0.995
        ) {
            return input
        }

        val topEdge = hypot((trX - tlX).toDouble(), (trY - tlY).toDouble())
        val bottomEdge = hypot((brX - blX).toDouble(), (brY - blY).toDouble())
        val leftEdge = hypot((blX - tlX).toDouble(), (blY - tlY).toDouble())
        val rightEdge = hypot((brX - trX).toDouble(), (brY - trY).toDouble())

        val outW = max(topEdge, bottomEdge).roundToInt().coerceIn(16, w)
        val outH = max(leftEdge, rightEdge).roundToInt().coerceIn(16, h)

        val srcPts = floatArrayOf(tlX, tlY, trX, trY, brX, brY, blX, blY)
        val dstPts = floatArrayOf(
            0f, 0f,
            outW.toFloat(), 0f,
            outW.toFloat(), outH.toFloat(),
            0f, outH.toFloat()
        )

        val polyMatrix = Matrix()
        if (!polyMatrix.setPolyToPoly(srcPts, 0, dstPts, 0, 4)) {
            return input
        }

        val output = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(output)
        canvas.drawColor(Color.WHITE)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(input, polyMatrix, paint)
        return output
    }

    private fun scaleBitmapDown(input: Bitmap, maxDim: Int): Bitmap {
        val w = input.width
        val h = input.height
        if (w <= maxDim && h <= maxDim) return input

        val targetW: Int
        val targetH: Int
        if (w >= h) {
            targetW = maxDim
            targetH = ((h.toDouble() * maxDim) / w.toDouble()).roundToInt().coerceAtLeast(1)
        } else {
            targetH = maxDim
            targetW = ((w.toDouble() * maxDim) / h.toDouble()).roundToInt().coerceAtLeast(1)
        }
        return Bitmap.createScaledBitmap(input, targetW, targetH, true)
    }

    private fun stitchBitmapsVertically(top: Bitmap, bottom: Bitmap): Bitmap {
        val targetW = max(top.width, bottom.width)
        val topScaled = if (top.width == targetW) {
            top
        } else {
            val h = ((top.height.toDouble() * targetW) / top.width.toDouble()).roundToInt().coerceAtLeast(1)
            Bitmap.createScaledBitmap(top, targetW, h, true)
        }
        val bottomScaled = if (bottom.width == targetW) {
            bottom
        } else {
            val h = ((bottom.height.toDouble() * targetW) / bottom.width.toDouble()).roundToInt().coerceAtLeast(1)
            Bitmap.createScaledBitmap(bottom, targetW, h, true)
        }

        val gap = 12
        val totalH = topScaled.height + gap + bottomScaled.height
        val combined = Bitmap.createBitmap(targetW, totalH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(combined)
        canvas.drawColor(Color.WHITE)
        canvas.drawBitmap(topScaled, 0f, 0f, null)
        canvas.drawBitmap(bottomScaled, 0f, (topScaled.height + gap).toFloat(), null)

        if (topScaled !== top) topScaled.recycle()
        if (bottomScaled !== bottom) bottomScaled.recycle()
        return combined
    }

    private fun saveToPublicDocuments(fileName: String, bytes: ByteArray): String {
        val publicDocsRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS)
        val targetDir = File(publicDocsRoot, "PDF Maker")

        try {
            if (!targetDir.exists()) {
                targetDir.mkdirs()
            }
            val targetFile = File(targetDir, fileName)
            FileOutputStream(targetFile).use { fos ->
                fos.write(bytes)
                fos.flush()
            }
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(targetFile.absolutePath),
                arrayOf("application/pdf"),
                null
            )
            return targetFile.absolutePath
        } catch (_: Exception) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = applicationContext.contentResolver
                val contentValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOCUMENTS + "/PDF Maker"
                    )
                }
                val uri = resolver.insert(MediaStore.Files.getContentUri("external"), contentValues)
                    ?: throw IllegalStateException("Could not create MediaStore entry in public Documents")
                resolver.openOutputStream(uri)?.use { os ->
                    os.write(bytes)
                    os.flush()
                }

                // Query the actual data path if available
                var actualPath = File(targetDir, fileName).absolutePath
                try {
                    resolver.query(uri, arrayOf(MediaStore.MediaColumns.DATA), null, null, null)?.use { cursor ->
                        if (cursor.moveToFirst()) {
                            val idx = cursor.getColumnIndex(MediaStore.MediaColumns.DATA)
                            if (idx >= 0) {
                                val p = cursor.getString(idx)
                                if (!p.isNullOrBlank()) actualPath = p
                            }
                        }
                    }
                } catch (_: Exception) {}

                return actualPath
            }
            throw IllegalStateException("Unable to write to public Documents directory")
        }
    }

    private fun exportFileToPublicDownloads(sourcePath: String, fileName: String): String {
        val bytes = if (sourcePath.startsWith("content://")) {
            applicationContext.contentResolver.openInputStream(Uri.parse(sourcePath))?.use { it.readBytes() }
                ?: throw IllegalStateException("Could not read content URI: $sourcePath")
        } else {
            val sourceFile = File(sourcePath)
            if (!sourceFile.exists()) {
                throw IllegalStateException("Source PDF does not exist: $sourcePath")
            }
            sourceFile.readBytes()
        }

        val publicDownloadsRoot = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val targetDir = File(publicDownloadsRoot, "PDF Maker")

        try {
            if (!targetDir.exists()) {
                targetDir.mkdirs()
            }
            var targetFile = File(targetDir, fileName)
            val baseName = fileName.removeSuffix(".pdf")
            var counter = 1
            while (targetFile.exists() && targetFile.absolutePath != sourcePath) {
                targetFile = File(targetDir, "${baseName}_$counter.pdf")
                counter++
            }
            FileOutputStream(targetFile).use { fos ->
                fos.write(bytes)
                fos.flush()
            }
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(targetFile.absolutePath),
                arrayOf("application/pdf"),
                null
            )
            return targetFile.absolutePath
        } catch (_: Exception) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val resolver = applicationContext.contentResolver
                val contentValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                    put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                    put(
                        MediaStore.MediaColumns.RELATIVE_PATH,
                        Environment.DIRECTORY_DOWNLOADS + "/PDF Maker"
                    )
                }
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                    ?: throw IllegalStateException("Could not create MediaStore entry in Downloads")
                resolver.openOutputStream(uri)?.use { os ->
                    os.write(bytes)
                    os.flush()
                }
                return File(targetDir, fileName).absolutePath
            }
            throw IllegalStateException("Unable to export to public Downloads directory")
        }
    }
}
