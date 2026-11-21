package com.ytfl.attendmate

import android.content.Context
import android.content.Intent
import android.content.ActivityNotFoundException
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import android.provider.CalendarContract
import android.content.ContentValues
import android.content.ContentResolver
import android.content.ContentUris
import android.os.Bundle

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.attendmate.app/update"
    private val BUILD_CONFIG_CHANNEL = "com.attendmate.app/build_config"
    private val BATTERY_OPTIMIZATION_CHANNEL = "com.attendmate.app/battery_optimization"

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

        val CALENDAR_CHANNEL = "com.attendmate.app/calendar"
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALENDAR_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "pruneAttendMateEvents" -> {
                    val calendarId = call.argument<String>("calendarId")
                    try {
                        val count = pruneAttendMateEvents(calendarId)
                        result.success(count)
                    } catch (e: Exception) {
                        result.error("PRUNE_ERROR", e.message, null)
                    }
                }
                "deleteEvent" -> {
                    val eventId = call.argument<String>("eventId")
                    if (eventId != null) {
                        try {
                            val deleted = deleteCalendarEvent(eventId)
                            result.success(deleted)
                        } catch (e: Exception) {
                            result.error("DELETE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "eventId is required", null)
                    }
                }
                "setEventColor" -> {
                    val eventId = call.argument<String>("eventId")
                    val color = call.argument<Int>("color")
                    if (eventId != null && color != null) {
                        try {
                            val updated = setCalendarEventColor(eventId, color)
                            result.success(updated)
                        } catch (e: Exception) {
                            result.error("COLOR_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "eventId and color are required", null)
                    }
                }
                "triggerCalendarSync" -> {
                    val calendarId = call.argument<String>("calendarId")
                    try {
                        triggerCalendarSync(calendarId)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("SYNC_ERROR", e.message, null)
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
                "openFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        try {
                            val opened = openFile(filePath)
                            result.success(opened)
                        } catch (e: Exception) {
                            result.error("OPEN_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGUMENTS", "File path is required", null)
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
            FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
        } else {
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

    private fun openFile(filePath: String): Boolean {
        val file = File(filePath)
        if (!file.exists()) {
            throw Exception("File not found: $filePath")
        }

        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(
                this,
                "${packageName}.fileprovider",
                file
            )
        } else {
            Uri.fromFile(file)
        }

        val mimeType = when (file.extension.lowercase()) {
            "pdf" -> "application/pdf"
            "json" -> "application/json"
            "csv" -> "text/csv"
            "txt" -> "text/plain"
            else -> "*/*"
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        return try {
            val chooser = Intent.createChooser(intent, "Open file")
            chooser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(chooser)
            true
        } catch (e: ActivityNotFoundException) {
            false
        }
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

    private fun deleteCalendarEvent(eventId: String): Boolean {
        return try {
            val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId.toLong())
            val rows = contentResolver.delete(uri, null, null)
            rows > 0
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun pruneAttendMateEvents(calendarId: String?): Int {
        return try {
            val whereClause: String
            val selectionArgs: Array<String>
            if (calendarId != null && calendarId.isNotEmpty()) {
                whereClause = "${CalendarContract.Events.CALENDAR_ID} = ? AND (${CalendarContract.Events.DESCRIPTION} LIKE ? OR LOWER(${CalendarContract.Events.DESCRIPTION}) LIKE ?)"
                selectionArgs = arrayOf(calendarId, "%Imported from AttendMate%", "%attendmate%")
            } else {
                whereClause = "(${CalendarContract.Events.DESCRIPTION} LIKE ? OR LOWER(${CalendarContract.Events.DESCRIPTION}) LIKE ?)"
                selectionArgs = arrayOf("%Imported from AttendMate%", "%attendmate%")
            }
            val deleted = contentResolver.delete(CalendarContract.Events.CONTENT_URI, whereClause, selectionArgs)
            deleted
        } catch (e: Exception) {
            e.printStackTrace()
            0
        }
    }

    data class GoogleColor(val key: String, val color: Int)

    private val GOOGLE_CALENDAR_PALETTE = listOf(
        GoogleColor("1", 0xFF7986CB.toInt()), // Lavender
        GoogleColor("2", 0xFF33B679.toInt()), // Sage
        GoogleColor("3", 0xFF8E24AA.toInt()), // Grape
        GoogleColor("4", 0xFFE67C73.toInt()), // Flamingo
        GoogleColor("5", 0xFFF6BF26.toInt()), // Banana
        GoogleColor("6", 0xFFF4511E.toInt()), // Tangerine
        GoogleColor("7", 0xFF039BE5.toInt()), // Peacock
        GoogleColor("8", 0xFF616161.toInt()), // Graphite
        GoogleColor("9", 0xFF3F51B5.toInt()), // Blueberry
        GoogleColor("10", 0xFF0B8043.toInt()), // Basil
        GoogleColor("11", 0xFFD50000.toInt())  // Tomato
    )

    private fun findClosestGoogleColor(color: Int): GoogleColor {
        val r = (color shr 16) and 0xFF
        val g = (color shr 8) and 0xFF
        val b = color and 0xFF

        var closest = GOOGLE_CALENDAR_PALETTE[0]
        var minDistance = Long.MAX_VALUE

        for (palette in GOOGLE_CALENDAR_PALETTE) {
            val pr = (palette.color shr 16) and 0xFF
            val pg = (palette.color shr 8) and 0xFF
            val pb = palette.color and 0xFF

            val dr = (r - pr).toLong()
            val dg = (g - pg).toLong()
            val db = (b - pb).toLong()
            val distance = dr * dr + dg * dg + db * db

            if (distance < minDistance) {
                minDistance = distance
                closest = palette
            }
        }
        return closest
    }

    private fun setCalendarEventColor(eventId: String, color: Int): Boolean {
        return try {
            var accountName: String? = null
            var accountType: String? = null
            var calendarId: String? = null

            // 1. Look up calendarId, accountName, and accountType for this event
            contentResolver.query(
                CalendarContract.Events.CONTENT_URI,
                arrayOf(CalendarContract.Events.CALENDAR_ID),
                "${CalendarContract.Events._ID} = ?",
                arrayOf(eventId),
                null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    calendarId = cursor.getString(0)
                }
            }

            if (calendarId != null) {
                contentResolver.query(
                    CalendarContract.Calendars.CONTENT_URI,
                    arrayOf(CalendarContract.Calendars.ACCOUNT_NAME, CalendarContract.Calendars.ACCOUNT_TYPE),
                    "${CalendarContract.Calendars._ID} = ?",
                    arrayOf(calendarId),
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        accountName = cursor.getString(0)
                        accountType = cursor.getString(1)
                    }
                }
            }

            // 2. Query available EVENT colors from CalendarContract.Colors table for this device/account
            var bestColorKey: String? = null
            var bestColorVal: Int? = null
            var minDistance = Long.MAX_VALUE

            val r = (color shr 16) and 0xFF
            val g = (color shr 8) and 0xFF
            val b = color and 0xFF

            try {
                val colorsProjection = arrayOf(
                    CalendarContract.Colors.COLOR_KEY,
                    CalendarContract.Colors.COLOR
                )
                val colorsSelection = "${CalendarContract.Colors.COLOR_TYPE} = ?"
                val colorsArgs = arrayOf(CalendarContract.Colors.TYPE_EVENT.toString())

                contentResolver.query(
                    CalendarContract.Colors.CONTENT_URI,
                    colorsProjection,
                    colorsSelection,
                    colorsArgs,
                    null
                )?.use { cursor ->
                    while (cursor.moveToNext()) {
                        val cKey = cursor.getString(0)
                        val cVal = cursor.getInt(1)

                        val cr = (cVal shr 16) and 0xFF
                        val cg = (cVal shr 8) and 0xFF
                        val cb = cVal and 0xFF

                        val dr = (r - cr).toLong()
                        val dg = (g - cg).toLong()
                        val db = (b - cb).toLong()
                        val distance = dr * dr + dg * dg + db * db

                        if (distance < minDistance) {
                            minDistance = distance
                            bestColorKey = cKey
                            bestColorVal = cVal
                        }
                    }
                }
            } catch (ce: Exception) {
                ce.printStackTrace()
            }

            // Fallback to Google Palette if Colors table is empty or inaccessible
            if (bestColorKey == null) {
                val closest = findClosestGoogleColor(color)
                bestColorKey = closest.key
                bestColorVal = closest.color
            }

            // 3. Step A: Update EVENT_COLOR_KEY only (sanctioned Android path for non-sync-adapters)
            // Android's CalendarProvider automatically sets EVENT_COLOR from the key without throwing IllegalArgumentException
            var updated = false
            try {
                val values = ContentValues().apply {
                    put(CalendarContract.Events.EVENT_COLOR_KEY, bestColorKey)
                }
                val rows = contentResolver.update(
                    CalendarContract.Events.CONTENT_URI,
                    values,
                    "${CalendarContract.Events._ID} = ?",
                    arrayOf(eventId)
                )
                updated = rows > 0
            } catch (e: Exception) {
                e.printStackTrace()
            }

            // 4. Step B: If EVENT_COLOR_KEY was rejected (e.g. OEM or local offline calendars), update with CALLER_IS_SYNCADAPTER
            if (!updated && accountName != null && accountType != null) {
                try {
                    val syncUri = CalendarContract.Events.CONTENT_URI.buildUpon()
                        .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, accountName)
                        .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, accountType)
                        .build()

                    val syncValues = ContentValues().apply {
                        if (bestColorVal != null) {
                            put(CalendarContract.Events.EVENT_COLOR, bestColorVal)
                        }
                        put(CalendarContract.Events.EVENT_COLOR_KEY, bestColorKey)
                        put(CalendarContract.Events.DIRTY, 1)
                    }
                    val rows = contentResolver.update(
                        syncUri,
                        syncValues,
                        "${CalendarContract.Events._ID} = ?",
                        arrayOf(eventId)
                    )
                    updated = rows > 0
                } catch (e: Exception) {
                    e.printStackTrace()
                }
            }

            updated
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun triggerCalendarSync(calendarId: String? = null) {
        try {
            var account: android.accounts.Account? = null
            if (calendarId != null && calendarId.isNotEmpty()) {
                contentResolver.query(
                    CalendarContract.Calendars.CONTENT_URI,
                    arrayOf(CalendarContract.Calendars.ACCOUNT_NAME, CalendarContract.Calendars.ACCOUNT_TYPE),
                    "${CalendarContract.Calendars._ID} = ?",
                    arrayOf(calendarId),
                    null
                )?.use { cursor ->
                    if (cursor.moveToFirst()) {
                        val name = cursor.getString(0)
                        val type = cursor.getString(1)
                        if (!name.isNullOrEmpty() && !type.isNullOrEmpty()) {
                            account = android.accounts.Account(name, type)
                        }
                    }
                }
            }

            val bundle = Bundle().apply {
                putBoolean(ContentResolver.SYNC_EXTRAS_MANUAL, true)
            }
            ContentResolver.requestSync(account, CalendarContract.AUTHORITY, bundle)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }
}
