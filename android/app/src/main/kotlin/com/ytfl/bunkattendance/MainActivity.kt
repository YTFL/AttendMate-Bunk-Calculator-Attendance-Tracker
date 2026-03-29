package com.ytfl.bunkattendance

import android.content.Intent
import android.content.ActivityNotFoundException
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.attendmate.app/update"
    private val FILE_IMPORT_CHANNEL = "com.attendmate.app/file_import"
    private val FILE_PICKER_REQUEST_CODE = 9101
    private var pendingFileImportResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installAPK" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath != null) {
                        try {
                            val status = installAPK(apkPath)
                            result.success(status)
                        } catch (e: Exception) {
                            result.error("INSTALL_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "APK path is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_IMPORT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickImportFile" -> {
                    if (pendingFileImportResult != null) {
                        result.error("BUSY", "A file picker request is already in progress.", null)
                        return@setMethodCallHandler
                    }

                    pendingFileImportResult = result
                    openImportFilePicker()
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != FILE_PICKER_REQUEST_CODE) {
            return
        }

        val methodResult = pendingFileImportResult
        pendingFileImportResult = null

        if (methodResult == null) {
            return
        }

        if (resultCode != RESULT_OK || data?.data == null) {
            methodResult.error("CANCELLED", "File selection cancelled.", null)
            return
        }

        val uri = data.data!!
        try {
            val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() }
                ?: throw Exception("Unable to read selected file.")
            val name = queryDisplayName(uri) ?: "import_file"
            methodResult.success(mapOf("name" to name, "bytes" to bytes))
        } catch (e: Exception) {
            methodResult.error("READ_ERROR", e.message, null)
        }
    }

    private fun openImportFilePicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "*/*"
            putExtra(
                Intent.EXTRA_MIME_TYPES,
                arrayOf(
                    "application/json",
                    "text/csv",
                    "application/csv",
                    "text/comma-separated-values",
                    "text/plain"
                )
            )
        }

        startActivityForResult(intent, FILE_PICKER_REQUEST_CODE)
    }

    private fun queryDisplayName(uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            if (cursor != null && cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) cursor.getString(index) else null
            } else {
                null
            }
        } finally {
            cursor?.close()
        }
    }

    private fun installAPK(apkPath: String): String {
        val file = File(apkPath)
        if (!file.exists()) {
            throw Exception("APK file not found: $apkPath")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (!packageManager.canRequestPackageInstalls()) {
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                return "permission_required"
            }
        }

        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            // Use FileProvider for Android 7.0 and above
            FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
        } else {
            // Use file:// URI for older versions
            Uri.fromFile(file)
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            val chooser = Intent.createChooser(intent, "Install update")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chooser)
            "installer_started"
        } catch (e: ActivityNotFoundException) {
            "installer_not_found"
        }
    }
}
