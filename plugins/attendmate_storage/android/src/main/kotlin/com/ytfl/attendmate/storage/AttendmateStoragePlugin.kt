package com.ytfl.attendmate.storage

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.util.concurrent.Executors

class AttendmateStoragePlugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.NewIntentListener,
    MethodChannel.MethodCallHandler {

    companion object {
        private const val CHANNEL_NAME = "com.attendmate.app/file_import"
        private const val FILE_PICKER_REQUEST_CODE = 9101
        private const val DIR_PICKER_REQUEST_CODE = 9102
    }

    private var channel: MethodChannel? = null
    private var context: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private val backupIoExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingFileImportResult: MethodChannel.Result? = null
    private var pendingDirImportResult: MethodChannel.Result? = null
    private var initialOpenedFilePayload: Map<String, Any>? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME)
        channel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addOnNewIntentListener(this)

        handleViewFileIntent(binding.activity.intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeOnNewIntentListener(this)
        activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeOnNewIntentListener(this)
        activity = null
        activityBinding = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        handleViewFileIntent(intent)
        return false
    }

    private fun handleViewFileIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        if (Intent.ACTION_VIEW == action || Intent.ACTION_EDIT == action) {
            val uri = intent.data ?: return
            val ctx = activity ?: context ?: return
            try {
                val bytes = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return
                val name = queryDisplayName(ctx, uri) ?: "opened_file.json"
                val payload = mapOf("name" to name, "bytes" to bytes)
                initialOpenedFilePayload = payload

                channel?.invokeMethod("onFileOpened", payload)
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInitialOpenedFile" -> {
                val payload = initialOpenedFilePayload
                initialOpenedFilePayload = null
                result.success(payload)
            }
            "pickImportFile" -> {
                val act = activity
                if (act == null) {
                    result.error("NO_ACTIVITY", "Cannot pick file without foreground activity", null)
                    return
                }
                if (pendingFileImportResult != null) {
                    result.error("BUSY", "A file picker request is already in progress.", null)
                    return
                }
                pendingFileImportResult = result
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
                            "text/plain",
                            "*/*"
                        )
                    )
                }
                act.startActivityForResult(intent, FILE_PICKER_REQUEST_CODE)
            }
            "pickDirectory" -> {
                val act = activity
                if (act == null) {
                    result.error("NO_ACTIVITY", "Cannot pick directory without foreground activity", null)
                    return
                }
                if (pendingDirImportResult != null) {
                    result.error("BUSY", "A directory picker request is already in progress.", null)
                    return
                }
                pendingDirImportResult = result
                val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                    )
                }
                act.startActivityForResult(intent, DIR_PICKER_REQUEST_CODE)
            }
            "shareFile" -> {
                val fileName = call.argument<String>("fileName") ?: "export.json"
                val content = call.argument<String>("content") ?: ""
                val success = shareFileNative(fileName, content)
                result.success(success)
            }
            "shareText" -> {
                val title = call.argument<String>("title") ?: "Share AttendMate"
                val text = call.argument<String>("text") ?: ""
                val success = shareTextNative(title, text)
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
                            mainHandler.post { result.success(success) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("WRITE_ERROR", e.message, null) }
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
                            mainHandler.post { result.success(list) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("READ_ERROR", e.message, null) }
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
                            mainHandler.post { result.success(success) }
                        } catch (e: Exception) {
                            mainHandler.post { result.error("DELETE_ERROR", e.message, null) }
                        }
                    }
                } else {
                    result.error("INVALID_ARGS", "dirUri and fileName required", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == DIR_PICKER_REQUEST_CODE) {
            val dirResult = pendingDirImportResult
            pendingDirImportResult = null
            if (dirResult == null) return false

            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                dirResult.error("CANCELLED", "Directory selection cancelled.", null)
                return true
            }

            val treeUri = data.data!!
            try {
                val ctx = activity ?: context
                ctx?.contentResolver?.takePersistableUriPermission(
                    treeUri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            } catch (_: Exception) {}

            dirResult.success(treeUri.toString())
            return true
        }

        if (requestCode == FILE_PICKER_REQUEST_CODE) {
            val methodResult = pendingFileImportResult
            pendingFileImportResult = null
            if (methodResult == null) return false

            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                methodResult.error("CANCELLED", "File selection cancelled.", null)
                return true
            }

            val uri = data.data!!
            try {
                val ctx = activity ?: context ?: return false
                val bytes = ctx.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: throw Exception("Unable to read selected file.")
                val name = queryDisplayName(ctx, uri) ?: "import_file"
                methodResult.success(mapOf("name" to name, "bytes" to bytes))
            } catch (e: Exception) {
                methodResult.error("READ_ERROR", e.message, null)
            }
            return true
        }

        return false
    }

    private fun queryDisplayName(ctx: Context, uri: Uri): String? {
        var cursor: Cursor? = null
        return try {
            cursor = ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
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

    private fun shareFileNative(fileName: String, content: String): Boolean {
        val ctx = activity ?: context ?: return false
        return try {
            val cachePath = File(ctx.cacheDir, "shares")
            if (!cachePath.exists()) cachePath.mkdirs()
            val file = File(cachePath, fileName)
            file.writeText(content, Charsets.UTF_8)

            val uri = FileProvider.getUriForFile(ctx, "${ctx.packageName}.fileprovider", file)
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val chooser = Intent.createChooser(shareIntent, "Share Semester Data").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(chooser)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun shareTextNative(title: String, text: String): Boolean {
        val ctx = activity ?: context ?: return false
        return try {
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_TEXT, text)
            }
            val chooser = Intent.createChooser(shareIntent, title).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            ctx.startActivity(chooser)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun writeBackupFileNative(dirUriStr: String, fileName: String, content: String): Boolean {
        val ctx = activity ?: context ?: return false
        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(ctx, treeUri) ?: return false
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
            ctx.contentResolver.openOutputStream(newFile.uri)?.use { os ->
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
        val ctx = activity ?: context ?: return resultList

        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(ctx, treeUri) ?: return resultList
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
                            ctx.contentResolver.openInputStream(file.uri)?.use { isStream ->
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
        val ctx = activity ?: context ?: return false
        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(ctx, treeUri) ?: return false
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
