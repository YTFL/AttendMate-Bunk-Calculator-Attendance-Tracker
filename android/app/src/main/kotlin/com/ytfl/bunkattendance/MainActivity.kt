package com.ytfl.bunkattendance

import android.content.Intent
import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.attendmate.app/update"

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
