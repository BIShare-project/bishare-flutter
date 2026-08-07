package com.bishare.app

import android.app.UiModeManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
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
    private val appsChannelName = "app.bishare/apps"
    private val deviceChannelName = "app.bishare/device"
    private var shareChannel: MethodChannel? = null
    private var downloadsChannel: MethodChannel? = null
    private var clipboardChannel: MethodChannel? = null
    private var appsChannel: MethodChannel? = null
    private var deviceChannel: MethodChannel? = null

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
        // App Share: list launcher apps so Dart can stage their APKs.
        appsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appsChannelName)
        appsChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "list" -> listLauncherApps(result)
                else -> result.notImplemented()
            }
        }
        // Device kind: lets Dart pick the TV (Leanback) UI vs the touch UI.
        deviceChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, deviceChannelName)
        deviceChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "isTv" -> result.success(isTvDevice())
                else -> result.notImplemented()
            }
        }
        // The intent that launched us (cold start) may be a share.
        handleShareIntent(intent, initial = true)
    }

    /** True on Android TV / Leanback devices (no touchscreen, remote-driven). */
    private fun isTvDevice(): Boolean {
        val pm = packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            pm.hasSystemFeature(PackageManager.FEATURE_TELEVISION)
        ) {
            return true
        }
        val uiMode = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        return uiMode?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
    }

    /**
     * App Share (send installed apps as APKs). Visibility comes from the
     * MAIN/LAUNCHER `<queries>` declaration — deliberately NOT the Play-restricted
     * QUERY_ALL_PACKAGES, so only apps with a launcher icon are listed (which is
     * exactly the shareable set). Icon rasterizing for ~200 apps takes a moment,
     * so the query runs off the main thread; the result hops back to it.
     */
    private fun listLauncherApps(result: MethodChannel.Result) {
        val mainThread = Handler(Looper.getMainLooper())
        Thread {
            val apps = try {
                queryLauncherApps()
            } catch (e: Exception) {
                emptyList()
            }
            mainThread.post { result.success(apps) }
        }.start()
    }

    private fun queryLauncherApps(): List<Map<String, Any?>> {
        val pm = packageManager
        val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
        @Suppress("DEPRECATION")
        val resolved = if (Build.VERSION.SDK_INT >= 33) {
            pm.queryIntentActivities(launcher, PackageManager.ResolveInfoFlags.of(0L))
        } else {
            pm.queryIntentActivities(launcher, 0)
        }
        return resolved
            .mapNotNull { it.activityInfo?.applicationInfo }
            .distinctBy { it.packageName } // multiple launcher activities → one row
            .filter { it.packageName != packageName }
            .mapNotNull { app ->
                val apkPath = app.sourceDir ?: return@mapNotNull null
                val size = File(apkPath).length()
                if (size <= 0L) return@mapNotNull null
                mapOf(
                    "name" to app.loadLabel(pm).toString(),
                    "package" to app.packageName,
                    "version" to versionNameOf(app.packageName).orEmpty(),
                    "apkPath" to apkPath,
                    "sizeBytes" to size,
                    "splitCount" to (app.splitSourceDirs?.size ?: 0),
                    "icon" to iconPngOf(app),
                )
            }
            .sortedBy { (it["name"] as String).lowercase() }
    }

    private fun versionNameOf(pkg: String): String? = try {
        @Suppress("DEPRECATION")
        if (Build.VERSION.SDK_INT >= 33) {
            packageManager.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(0L)).versionName
        } else {
            packageManager.getPackageInfo(pkg, 0).versionName
        }
    } catch (e: Exception) {
        null
    }

    /** Rasterize the launcher icon (adaptive/vector safe) to a small PNG. */
    private fun iconPngOf(app: ApplicationInfo): ByteArray? = try {
        val drawable = app.loadIcon(packageManager)
        val px = 96
        val bitmap = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, px, px)
        drawable.draw(Canvas(bitmap))
        val out = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
        bitmap.recycle()
        out.toByteArray()
    } catch (e: Exception) {
        null
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
