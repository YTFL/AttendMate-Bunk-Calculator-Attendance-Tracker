package com.ytfl.attendmate

import android.content.Intent
import android.content.ActivityNotFoundException
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.provider.Settings
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.attendmate.app/update"
    private val FILE_IMPORT_CHANNEL = "com.attendmate.app/file_import"
    private val FILE_PICKER_REQUEST_CODE = 9101
    private val DIR_PICKER_REQUEST_CODE = 9102
    private var pendingFileImportResult: MethodChannel.Result? = null
    private var pendingDirImportResult: MethodChannel.Result? = null

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
                "pickDirectory" -> {
                    if (pendingDirImportResult != null) {
                        result.error("BUSY", "A directory picker request is already in progress.", null)
                        return@setMethodCallHandler
                    }

                    pendingDirImportResult = result
                    openDirectoryPicker()
                }
                "writeBackupFile" -> {
                    val dirUriStr = call.argument<String>("dirUri")
                    val fileName = call.argument<String>("fileName")
                    val content = call.argument<String>("content")
                    if (dirUriStr != null && fileName != null && content != null) {
                        try {
                            val success = writeBackupFileNative(dirUriStr, fileName, content)
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("WRITE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "dirUri, fileName, and content required", null)
                    }
                }
                "getBackupFiles" -> {
                    val dirUriStr = call.argument<String>("dirUri")
                    if (dirUriStr != null) {
                        try {
                            val list = getBackupFilesNative(dirUriStr)
                            result.success(list)
                        } catch (e: Exception) {
                            result.error("READ_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "dirUri is required", null)
                    }
                }
                "deleteBackupFile" -> {
                    val dirUriStr = call.argument<String>("dirUri")
                    val fileName = call.argument<String>("fileName")
                    if (dirUriStr != null && fileName != null) {
                        try {
                            val success = deleteBackupFileNative(dirUriStr, fileName)
                            result.success(success)
                        } catch (e: Exception) {
                            result.error("DELETE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "dirUri and fileName required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode == DIR_PICKER_REQUEST_CODE) {
            val dirResult = pendingDirImportResult
            pendingDirImportResult = null
            if (dirResult == null) return

            if (resultCode != RESULT_OK || data?.data == null) {
                dirResult.error("CANCELLED", "Directory selection cancelled.", null)
                return
            }

            val treeUri = data.data!!
            try {
                contentResolver.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: Exception) {}

            dirResult.success(treeUri.toString())
            return
        }

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

    private fun openDirectoryPicker() {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
        }
        startActivityForResult(intent, DIR_PICKER_REQUEST_CODE)
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

    private fun getPathFromTreeUri(uri: Uri): String? {
        val docId = try {
            DocumentsContract.getTreeDocumentId(uri)
        } catch (e: Exception) {
            uri.path
        } ?: return null

        val split = docId.split(":")
        if (split.size >= 2) {
            val type = split[0]
            val relativePath = split[1]
            if ("primary".equals(type, ignoreCase = true)) {
                val externalStorage = Environment.getExternalStorageDirectory().absolutePath
                val fullPath = if (relativePath.isNotEmpty()) "$externalStorage/$relativePath" else externalStorage
                val file = File(fullPath)
                if (!file.exists()) {
                    file.mkdirs()
                }
                return file.absolutePath
            } else {
                val fullPath = "/storage/$type/$relativePath"
                val file = File(fullPath)
                if (!file.exists()) {
                    file.mkdirs()
                }
                return file.absolutePath
            }
        }
        return null
    }

    private fun writeBackupFileNative(dirUriStr: String, fileName: String, content: String): Boolean {
        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(this, treeUri) ?: return false
            val existing = dir.findFile(fileName)
            existing?.delete()

            val newFile = dir.createFile("application/json", fileName) ?: return false
            contentResolver.openOutputStream(newFile.uri)?.use { os ->
                os.write(content.toByteArray(Charsets.UTF_8))
                os.flush()
            }
            return true
        } else {
            val dir = File(dirUriStr)
            if (!dir.exists()) {
                dir.mkdirs()
            }
            val file = File(dir, fileName)
            file.writeText(content, Charsets.UTF_8)
            return true
        }
    }

    private fun getBackupFilesNative(dirUriStr: String): List<Map<String, Any>> {
        val resultList = mutableListOf<Map<String, Any>>()
        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(this, treeUri) ?: return resultList
            val files = dir.listFiles()
            for (i in files.indices) {
                val file = files[i]
                val name = file.name ?: continue
                if (name.startsWith("attendmate_backup_") && name.endsWith(".json")) {
                    val bytes = file.length()
                    val lastMod = file.lastModified()
                    var textContent = ""
                    try {
                        contentResolver.openInputStream(file.uri)?.use { isStream ->
                            textContent = isStream.bufferedReader().use { it.readText() }
                        }
                    } catch (_: Exception) {}

                    resultList.add(mapOf(
                        "fileName" to name,
                        "fileSizeBytes" to bytes,
                        "lastModified" to lastMod,
                        "content" to textContent
                    ))
                }
            }
        } else {
            val dir = File(dirUriStr)
            if (dir.exists()) {
                val files = dir.listFiles()
                if (files != null) {
                    for (i in files.indices) {
                        val file = files[i]
                        if (file.isFile && file.name.startsWith("attendmate_backup_") && file.name.endsWith(".json")) {
                            var textContent = ""
                            try {
                                textContent = file.readText(Charsets.UTF_8)
                            } catch (_: Exception) {}

                            resultList.add(mapOf(
                                "fileName" to file.name,
                                "fileSizeBytes" to file.length(),
                                "lastModified" to file.lastModified(),
                                "content" to textContent
                            ))
                        }
                    }
                }
            }
        }
        return resultList
    }

    private fun deleteBackupFileNative(dirUriStr: String, fileName: String): Boolean {
        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(this, treeUri) ?: return false
            val file = dir.findFile(fileName) ?: return false
            return file.delete()
        } else {
            val file = File(dirUriStr, fileName)
            if (file.exists()) {
                return file.delete()
            }
            return false
        }
    }
}
