package com.ytfl.attendmate

import android.content.Context
import android.net.Uri
import androidx.documentfile.provider.DocumentFile
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class FileImportHandler(
    private val context: Context,
    private val activityProvider: () -> MainActivity? = { null }
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "com.attendmate.app/file_import"

        fun register(
            messenger: BinaryMessenger,
            context: Context,
            activityProvider: () -> MainActivity? = { null }
        ): MethodChannel {
            val channel = MethodChannel(messenger, CHANNEL_NAME)
            channel.setMethodCallHandler(FileImportHandler(context, activityProvider))
            return channel
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickImportFile" -> {
                val activity = activityProvider()
                if (activity == null) {
                    result.error("NO_ACTIVITY", "File picker requires foreground activity", null)
                    return
                }
                activity.openImportFilePickerForResult(result)
            }
            "pickDirectory" -> {
                val activity = activityProvider()
                if (activity == null) {
                    result.error("NO_ACTIVITY", "Directory picker requires foreground activity", null)
                    return
                }
                activity.openDirectoryPickerForResult(result)
            }
            "writeBackupFile" -> {
                val dirUriStr = call.argument<String>("dirUri")
                val fileName = call.argument<String>("fileName")
                val content = call.argument<String>("content")
                if (dirUriStr != null && fileName != null && content != null) {
                    try {
                        val success = writeBackupFileNative(context, dirUriStr, fileName, content)
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
                        val list = getBackupFilesNative(context, dirUriStr)
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
                        val success = deleteBackupFileNative(context, dirUriStr, fileName)
                        result.success(success)
                    } catch (e: Exception) {
                        result.error("DELETE_ERROR", e.message, null)
                    }
                } else {
                    result.error("INVALID_ARGS", "dirUri and fileName required", null)
                }
            }
            "getInitialOpenedFile" -> {
                val activity = activityProvider()
                if (activity != null) {
                    val payload = activity.consumeInitialOpenedFilePayload()
                    result.success(payload)
                } else {
                    result.success(null)
                }
            }
            "shareFile" -> {
                val fileName = call.argument<String>("fileName")
                val content = call.argument<String>("content")
                val activity = activityProvider()
                if (fileName != null && content != null && activity != null) {
                    val success = activity.shareFileNative(fileName, content)
                    result.success(success)
                } else {
                    result.error("INVALID_ARGS", "fileName, content, and activity required", null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun writeBackupFileNative(ctx: Context, dirUriStr: String, fileName: String, content: String): Boolean {
        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(ctx, treeUri) ?: return false
            val existing = dir.findFile(fileName)
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

    private fun getBackupFilesNative(ctx: Context, dirUriStr: String): List<Map<String, Any>> {
        val resultList = mutableListOf<Map<String, Any>>()
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
                    try {
                        ctx.contentResolver.openInputStream(file.uri)?.use { isStream ->
                            textContent = isStream.bufferedReader().use { it.readText() }
                        }
                    } catch (_: Exception) {}

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
                            try {
                                textContent = file.readText(Charsets.UTF_8)
                            } catch (_: Exception) {}

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

    private fun deleteBackupFileNative(ctx: Context, dirUriStr: String, fileName: String): Boolean {
        if (dirUriStr.startsWith("content://")) {
            val treeUri = Uri.parse(dirUriStr)
            val dir = DocumentFile.fromTreeUri(ctx, treeUri) ?: return false
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
