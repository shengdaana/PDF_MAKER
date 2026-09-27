package com.introbird.pdfmakerflutter

import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.introbird.pdfmakerflutter/native_files"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openPdf" -> {
                        val filePath = call.argument<String>("path")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "File path is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = File(filePath)
                            if (!file.exists()) {
                                result.error("FILE_NOT_FOUND", "PDF file does not exist: $filePath", null)
                                return@setMethodCallHandler
                            }
                            val authority = "${applicationContext.packageName}.fileprovider"
                            val contentUri: Uri = FileProvider.getUriForFile(this, authority, file)

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

                    "savePdfToPublicDocuments" -> {
                        val fileName = call.argument<String>("fileName")
                        val bytes = call.argument<ByteArray>("bytes")
                        if (fileName.isNullOrBlank() || bytes == null) {
                            result.error("INVALID_ARGS", "Missing fileName or bytes", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val savedPath = saveToPublicDocuments(fileName, bytes)
                            result.success(savedPath)
                        } catch (e: Exception) {
                            result.error("SAVE_ERROR", e.localizedMessage ?: "Failed to save PDF", null)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Saves PDF bytes to public device storage (/storage/emulated/0/Documents/PDF Maker/)
     * so that generated PDFs ALWAYS survive app uninstallation (FIX 4).
     */
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
            // Scoped storage MediaStore fallback for strict Android 10 (API 29) devices
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
                return File(targetDir, fileName).absolutePath
            }
            throw IllegalStateException("Unable to write to public Documents directory")
        }
    }
}
