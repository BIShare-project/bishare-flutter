package com.bishare.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
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
    private val clipboardChannelName = "app.bishare/clipboard"
    private var shareChannel: MethodChannel? = null
    private var downloadsChannel: MethodChannel? = null
    private var clipboardChannel: MethodChannel? = null

    /// Cheap clipboard generation counter for the Dart poll loop (mirrors
    /// NSPasteboard.changeCount). Bumped by the primary-clip listener; note
    /// Android 10+ only delivers clip events while the app has focus, so the
    /// counter (like clipboard reads themselves) is foreground-only.
    private var clipChanges = 0
    private var clipListener: ClipboardManager.OnPrimaryClipChangedListener? = null
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
        // Image clipboard for Universal Clipboard sync (Flutter's Clipboard API
        // is text-only). See ClipboardImageChannel on the Dart side.
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        if (clipListener == null) {
            clipListener = ClipboardManager.OnPrimaryClipChangedListener { clipChanges++ }
            clipboard.addPrimaryClipChangedListener(clipListener)
        }
        clipboardChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, clipboardChannelName)
        clipboardChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "getImage" -> result.success(clipboardImage(clipboard))
                "setImage" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val mime = call.argument<String>("mime") ?: "image/png"
                    result.success(setClipboardImage(clipboard, bytes, mime))
                }
                "changeCount" -> result.success(clipChanges)
                else -> result.notImplemented()
            }
        }
        // The intent that launched us (cold start) may be a share.
        handleShareIntent(intent, initial = true)
    }

    /** Read the primary clip's image (a content:// item) as `{bytes, mime}`, or null. */
    private fun clipboardImage(clipboard: ClipboardManager): Map<String, Any>? {
        return try {
            val clip = clipboard.primaryClip ?: return null
            val description = clip.description
            var mime: String? = null
            for (i in 0 until description.mimeTypeCount) {
                val t = description.getMimeType(i)
                if (t.startsWith("image/")) { mime = t; break }
            }
            for (i in 0 until clip.itemCount) {
                val uri = clip.getItemAt(i).uri ?: continue
                val resolvedMime = contentResolver.getType(uri) ?: mime ?: continue
                if (!resolvedMime.startsWith("image/")) continue
                val bytes = contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: continue
                if (bytes.isEmpty()) continue
                return mapOf("bytes" to bytes, "mime" to resolvedMime)
            }
            null
        } catch (e: Exception) {
            null // no permission / provider gone — clipboard reads are best-effort
        }
    }

    /**
     * Put encoded image bytes on the clipboard: stage them in cache/clipboard/
     * and clip a FileProvider content:// URI (the system clipboard grants the
     * pasting app read access to clip URIs).
     */
    private fun setClipboardImage(clipboard: ClipboardManager, bytes: ByteArray?, mime: String): Boolean {
        if (bytes == null || bytes.isEmpty()) return false
        return try {
            val dir = File(cacheDir, "clipboard").apply { mkdirs() }
            // A single rotating name keeps stale staged clips from accumulating.
            val ext = when (mime) {
                "image/jpeg" -> "jpg"
                "image/gif" -> "gif"
                "image/webp" -> "webp"
                else -> "png"
            }
            val file = File(dir, "clip.$ext")
            file.writeBytes(bytes)
            val uri = FileProvider.getUriForFile(this, "$packageName.clipboard", file)
            clipboard.setPrimaryClip(ClipData.newUri(contentResolver, "image", uri))
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Android 10+ only delivers OnPrimaryClipChanged while the app has focus, so
     * an image copied in another app while we were backgrounded never bumps
     * [clipChanges] and the Dart poll skips it. Bump once on focus-gain so exactly
     * one clipboard re-read happens on resume, catching that missed copy.
     */
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) clipChanges++
    }

    override fun onDestroy() {
        clipListener?.let {
            (getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager)
                .removePrimaryClipChangedListener(it)
        }
        clipListener = null
        super.onDestroy()
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
