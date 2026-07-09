package com.bishare.app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native share-target handling — replaces the receive_sharing_intent plugin.
 *
 * When another app shares files into BIShare (ACTION_SEND / ACTION_SEND_MULTIPLE),
 * we copy the incoming content:// streams into our cache and hand the local file
 * paths to Dart over a MethodChannel. Dart drops them into the compose tray.
 *
 * Cold start: the launching intent is captured in [configureFlutterEngine] and
 * buffered in [pending] until Dart pulls it via `getInitialShare`.
 * Warm start: [onNewIntent] pushes paths straight to Dart via `onShare`
 * (MainActivity is launchMode=singleTop, so resumes reuse this instance).
 */
class MainActivity : FlutterActivity() {
    private val shareChannelName = "app.bishare/share"
    private val downloadsChannelName = "app.bishare/android_downloads"
    private var shareChannel: MethodChannel? = null
    private var downloadsChannel: MethodChannel? = null
    private var pending: List<String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Share channel (existing)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
        shareChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    result.success(pending)
                    pending = null
                }
                else -> result.notImplemented()
            }
        }
        // Android Downloads channel: get public Downloads directory
        downloadsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannelName)
        downloadsChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getPublicDownloads" -> {
                    // Return public Downloads path (e.g. /storage/emulated/0/Download)
                    // Works on all Android versions, no permissions needed on Android 10+
                    val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                    result.success(downloadsDir.absolutePath)
                }
                else -> result.notImplemented()
            }
        }
        // The intent that launched us (cold start) may be a share.
        handleShareIntent(intent, initial = true)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShareIntent(intent, initial = false)
    }

    private fun handleShareIntent(intent: Intent?, initial: Boolean) {
        intent ?: return
        val uris = ArrayList<Uri>()
        when (intent.action) {
            Intent.ACTION_SEND -> extractStream(intent)?.let { uris.add(it) }
            Intent.ACTION_SEND_MULTIPLE -> extractStreams(intent)?.let { uris.addAll(it) }
            else -> return
        }
        if (uris.isEmpty()) return

        val paths = uris.mapNotNull { copyToCache(it) }
        // Consume the intent so a rotation / resume doesn't re-deliver the share.
        intent.action = null
        intent.removeExtra(Intent.EXTRA_STREAM)
        if (paths.isEmpty()) return

        if (initial) {
            pending = paths
        } else {
            shareChannel?.invokeMethod("onShare", paths)
        }
    }

    @Suppress("DEPRECATION")
    private fun extractStream(intent: Intent): Uri? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra(Intent.EXTRA_STREAM)
        }

    @Suppress("DEPRECATION")
    private fun extractStreams(intent: Intent): ArrayList<Uri>? =
        if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM)
        }

    /** Copy a shared content:// (or file://) URI into cache; returns its path. */
    private fun copyToCache(uri: Uri): String? {
        return try {
            val name = queryName(uri) ?: "shared-${System.currentTimeMillis()}"
            val dir = File(cacheDir, "shared").apply { mkdirs() }
            var out = File(dir, name)
            // Avoid clobbering a same-named file from a previous share.
            if (out.exists()) {
                val dot = name.lastIndexOf('.')
                val stem = if (dot > 0) name.substring(0, dot) else name
                val ext = if (dot > 0) name.substring(dot) else ""
                out = File(dir, "$stem-${System.currentTimeMillis()}$ext")
            }
            contentResolver.openInputStream(uri)?.use { input ->
                out.outputStream().use { input.copyTo(it) }
            } ?: return null
            out.absolutePath
        } catch (e: Exception) {
            null
        }
    }

    private fun queryName(uri: Uri): String? {
        if (uri.scheme == "file") return uri.lastPathSegment
        var name: String? = null
        contentResolver.query(uri, null, null, null, null)?.use { c ->
            val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (idx >= 0 && c.moveToFirst()) name = c.getString(idx)
        }
        return name
    }
}
