package com.ytfl.attendmate

import android.content.Context
import android.content.Intent
import android.content.ActivityNotFoundException
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
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
    private val BUILD_CONFIG_CHANNEL = "com.attendmate.app/build_config"
    private val FILE_IMPORT_CHANNEL = "com.attendmate.app/file_import"
    private val BATTERY_OPTIMIZATION_CHANNEL = "com.attendmate.app/battery_optimization"
    private val FILE_PICKER_REQUEST_CODE = 9101
    private val DIR_PICKER_REQUEST_CODE = 9102
    private var pendingFileImportResult: MethodChannel.Result? = null
    private var pendingDirImportResult: MethodChannel.Result? = null
    private var initialOpenedFilePayload: Map<String, Any>? = null
    private var fileChannel: MethodChannel? = null
    private val backupIoExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUILD_CONFIG_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGoogleClientId" -> result.success(BuildConfig.GOOGLE_CLIENT_ID)
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_OPTIMIZATION_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    try {
                        result.success(isIgnoringBatteryOptimizations())
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "requestIgnoreBatteryOptimizations" -> {
                    try {
                        result.success(requestIgnoreBatteryOptimizations())
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                "openBatteryOptimizationSettings" -> {
                    try {
                        result.success(openBatteryOptimizationSettings())
                    } catch (e: Exception) {
                        result.error("ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

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

        fileChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILE_IMPORT_CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialOpenedFile" -> {
                        val payload = consumeInitialOpenedFilePayload()
                        result.success(payload)
                    }
                    "pickImportFile" -> openImportFilePickerForResult(result)
                    "pickDirectory" -> openDirectoryPickerForResult(result)
                    "shareFile" -> {
                        val fileName = call.argument<String>("fileName") ?: "export.json"
                        val content = call.argument<String>("content") ?: ""
                        val success = shareFileNative(fileName, content)
                        result.success(success)
                    }
                    "writeBackupFile" -> {
                        val dirUriStr = call.argument<String>("dirUri")
                        val fileName = call.argument<String>("fileName")
                        val content = call.argument<String>("content")
                        if (dirUriStr != null && fileName != null && content != null) {
                            backupIoExecutor.execute {
                                try {
                                    val success = writeBackupFileNative(dirUriStr, fileName, content)
                                    runOnUiThread { result.success(success) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("WRITE_ERROR", e.message, null) }
                                }
                            }
                        } else {
                            result.error("INVALID_ARGS", "dirUri, fileName, and content required", null)
                        }
                    }
                    "getBackupFiles" -> {
                        val dirUriStr = call.argument<String>("dirUri")
                        val includeContent = call.argument<Boolean>("includeContent") ?: true
                        if (dirUriStr != null) {
                            backupIoExecutor.execute {
                                try {
                                    val list = getBackupFilesNative(dirUriStr, includeContent)
                                    runOnUiThread { result.success(list) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("READ_ERROR", e.message, null) }
                                }
                            }
                        } else {
                            result.error("INVALID_ARGS", "dirUri is required", null)
                        }
                    }
                    "deleteBackupFile" -> {
                        val dirUriStr = call.argument<String>("dirUri")
                        val fileName = call.argument<String>("fileName")
                        if (dirUriStr != null && fileName != null) {
                            backupIoExecutor.execute {
                                try {
                                    val success = deleteBackupFileNative(dirUriStr, fileName)
                                    runOnUiThread { result.success(success) }
                                } catch (e: Exception) {
                                    runOnUiThread { result.error("DELETE_ERROR", e.message, null) }
                                }
                            }
                        } else {
                            result.error("INVALID_ARGS", "dirUri and fileName required", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

        // Process file VIEW/EDIT intent if app launched via clicking a file
        intent?.let { handleViewFileIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleViewFileIntent(intent)
    }

    private fun handleViewFileIntent(intent: Intent) {
        val action = intent.action
        if (Intent.ACTION_VIEW == action || Intent.ACTION_EDIT == action) {
            val uri = intent.data ?: return
            try {
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return
                val name = queryDisplayName(uri) ?: "opened_file.json"
                val payload = mapOf("name" to name, "bytes" to bytes)
                initialOpenedFilePayload = payload

                fileChannel?.invokeMethod("onFileOpened", payload)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    fun consumeInitialOpenedFilePayload(): Map<String, Any>? {
        val payload = initialOpenedFilePayload
        initialOpenedFilePayload = null
        return payload
    }

    fun shareFileNative(fileName: String, content: String): Boolean {
        return try {
            val cachePath = File(cacheDir, "shares")
            if (!cachePath.exists()) cachePath.mkdirs()
            val file = File(cachePath, fileName)
            file.writeText(content, Charsets.UTF_8)

            val uri = FileProvider.getUriForFile(this, "${packageName}.fileprovider", file)
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(shareIntent, "Share Semester Data")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chooser)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    fun openImportFilePickerForResult(result: MethodChannel.Result) {
        if (pendingFileImportResult != null) {
            result.error("BUSY", "A file picker request is already in progress.", null)
            return
        }
        pendingFileImportResult = result
        openImportFilePicker()
    }

    fun openDirectoryPickerForResult(result: MethodChannel.Result) {
        if (pendingDirImportResult != null) {
            result.error("BUSY", "A directory picker request is already in progress.", null)
            return
        }
        pendingDirImportResult = result
        openDirectoryPicker()
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

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as? PowerManager
            val isIgnoring = powerManager?.isIgnoringBatteryOptimizations(packageName) ?: true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as? android.app.ActivityManager
                val isRestricted = activityManager?.isBackgroundRestricted ?: false
                return isIgnoring && !isRestricted
            }
            return isIgnoring
        }
        return true
    }

    private fun requestIgnoreBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (isIgnoringBatteryOptimizations()) {
                return true
            }
            return try {
                val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                true
            } catch (e: Exception) {
                e.printStackTrace()
                openBatteryOptimizationSettings()
            }
        }
        return true
    }

    private fun openBatteryOptimizationSettings(): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            try {
                val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                    data = Uri.parse("package:$packageName")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                startActivity(intent)
                true
            } catch (ex: Exception) {
                ex.printStackTrace()
                false
            }
        }
    }

    private fun writeBackupFileNative(dirUriStr: String, fileName: String, content: String): Boolean {
        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(applicationContext, treeUri) ?: return false
            var existing = dir.findFile(fileName)
            if (existing == null) {
                for (f in dir.listFiles()) {
                    val n = f.name ?: continue
                    if (n == fileName || n == "$fileName.json" || "$n.json" == fileName) {
                        existing = f
                        break
                    }
                }
            }
            existing?.delete()

            val newFile = dir.createFile("application/json", fileName) ?: return false
            applicationContext.contentResolver.openOutputStream(newFile.uri)?.use { os ->
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

    private fun getBackupFilesNative(dirUriStr: String, includeContent: Boolean = true): List<Map<String, Any>> {
        val resultList = mutableListOf<Map<String, Any>>()
        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(applicationContext, treeUri) ?: return resultList
            val files = dir.listFiles()
            for (i in files.indices) {
                val file = files[i]
                val name = file.name ?: continue
                if (name.startsWith("attendmate_backup_") && name.endsWith(".json")) {
                    val bytes = file.length()
                    val lastMod = file.lastModified()
                    var textContent = ""
                    if (includeContent) {
                        try {
                            applicationContext.contentResolver.openInputStream(file.uri)?.use { isStream ->
                                textContent = isStream.bufferedReader().use { it.readText() }
                            }
                        } catch (_: Exception) {}
                    }

                    resultList.add(
                        mapOf(
                            "fileName" to name,
                            "fileSizeBytes" to bytes,
                            "lastModified" to lastMod,
                            "content" to textContent
                        )
                    )
                }
            }
        } else {
            val dir = File(dirUriStr)
            if (dir.exists()) {
                val files = dir.listFiles()
                if (files != null) {
                    for (file in files) {
                        val name = file.name
                        if (name.startsWith("attendmate_backup_") && name.endsWith(".json")) {
                            var textContent = ""
                            if (includeContent) {
                                try {
                                    textContent = file.readText(Charsets.UTF_8)
                                } catch (_: Exception) {}
                            }

                            resultList.add(
                                mapOf(
                                    "fileName" to name,
                                    "fileSizeBytes" to file.length(),
                                    "lastModified" to file.lastModified(),
                                    "content" to textContent
                                )
                            )
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
            val dir = DocumentFile.fromTreeUri(applicationContext, treeUri) ?: return false
            var file = dir.findFile(fileName)
            if (file == null) {
                for (f in dir.listFiles()) {
                    val n = f.name ?: continue
                    if (n == fileName || n == "$fileName.json" || "$n.json" == fileName) {
                        file = f
                        break
                    }
                }
            }
            return file?.delete() ?: false
        } else {
            val file = File(dirUriStr, fileName)
            if (file.exists()) {
                return file.delete()
            }
            return false
        }
    }
}
