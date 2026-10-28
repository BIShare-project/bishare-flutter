package com.bishare.app

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * The folder the Send tab's Documents list reads (redesign-plan.md 3.6).
 *
 * Storage Access Framework, not all-files access: the person picks one folder
 * with ACTION_OPEN_DOCUMENT_TREE, the read grant is persisted, and the tree
 * is listed through DocumentsContract (no READ/MANAGE_EXTERNAL_STORAGE). A file
 * is copied into the cache only when it is chosen, because the sender needs a
 * real path.
 *
 * Methods on `app.bishare/folder` (the same channel as macOS's save folder;
 * these names are Android and iOS only): docsRestore, docsPick, docsList,
 * docsCopy, docsClear.
 */
class DocFolder(private val activity: Activity) {
    private val prefs = activity.getSharedPreferences("doc_folder", Context.MODE_PRIVATE)
    private val main = Handler(Looper.getMainLooper())
    private var pendingPick: MethodChannel.Result? = null

    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "docsRestore" -> result.success(current()?.let { describe(it) })
            "docsPick" -> pick(result)
            "docsList" -> background(result) { list() }
            "docsCopy" -> {
                val id = call.argument<String>("id")
                if (id == null) result.success(null) else background(result) { copy(Uri.parse(id)) }
            }
            "docsClear" -> {
                clear()
                result.success(null)
            }
            else -> return false
        }
        return true
    }

    /** Answers the pick started by [pick]; true when [requestCode] was ours. */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST) return false
        val result = pendingPick ?: return true
        pendingPick = null
        val tree = data?.data
        if (resultCode != Activity.RESULT_OK || tree == null) {
            result.success(null)
            return true
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            result.success(null)
            return true
        }
        // One folder at a time: let go of the one before.
        current()?.takeIf { it != tree }?.let { release(it) }
        prefs.edit().putString(KEY, tree.toString()).apply()
        result.success(describe(tree))
        return true
    }

    private fun pick(result: MethodChannel.Result) {
        pendingPick?.success(null)
        pendingPick = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
        )
        @Suppress("DEPRECATION")
        activity.startActivityForResult(intent, REQUEST)
    }

    /** The granted tree, or null when none was picked or the grant is gone. */
    private fun current(): Uri? {
        val saved = prefs.getString(KEY, null) ?: return null
        val uri = Uri.parse(saved)
        val held = activity.contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isReadPermission
        }
        if (!held) {
            prefs.edit().remove(KEY).apply()
            return null
        }
        return uri
    }

    private fun clear() {
        current()?.let { release(it) }
        prefs.edit().remove(KEY).apply()
    }

    private fun release(tree: Uri) {
        try {
            activity.contentResolver.releasePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        } catch (e: SecurityException) {
            // already gone
        }
    }

    private fun describe(tree: Uri): Map<String, Any?> {
        val doc = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        var name: String? = null
        try {
            activity.contentResolver.query(
                doc,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null,
            )?.use { c -> if (c.moveToFirst()) name = c.getString(0) }
        } catch (e: Exception) {
            // the provider may be gone; the name stays unknown
        }
        return mapOf("id" to tree.toString(), "name" to (name ?: tree.lastPathSegment))
    }

    /**
     * Every file under the tree, breadth first, a few levels deep and capped,
     * so a huge folder still answers quickly. Hidden entries are skipped.
     */
    private fun list(): List<Map<String, Any?>> {
        val tree = current() ?: return emptyList()
        val resolver = activity.contentResolver
        val columns = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val out = ArrayList<Map<String, Any?>>()
        val queue = ArrayDeque<Pair<String, Int>>()
        queue.add(DocumentsContract.getTreeDocumentId(tree) to 0)
        while (queue.isNotEmpty() && out.size < MAX_FILES) {
            val (parent, depth) = queue.removeFirst()
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
            try {
                resolver.query(children, columns, null, null, null)?.use { c ->
                    while (c.moveToNext() && out.size < MAX_FILES) {
                        val id = c.getString(0) ?: continue
                        val name = c.getString(1) ?: continue
                        if (name.startsWith(".")) continue
                        val mime = c.getString(2)
                        if (mime == DocumentsContract.Document.MIME_TYPE_DIR) {
                            if (depth < MAX_DEPTH) queue.add(id to depth + 1)
                            continue
                        }
                        out.add(
                            mapOf(
                                "id" to DocumentsContract.buildDocumentUriUsingTree(tree, id).toString(),
                                "name" to name,
                                "mime" to mime,
                                "size" to (if (c.isNull(3)) 0L else c.getLong(3)),
                                "modified" to (if (c.isNull(4)) 0L else c.getLong(4)),
                            ),
                        )
                    }
                }
            } catch (e: Exception) {
                // an unreadable subfolder is skipped
            }
        }
        return out
    }

    /** Copies one document into the cache; the path, or null on failure. */
    private fun copy(uri: Uri): String? {
        val resolver = activity.contentResolver
        var name = "document"
        var modified = 0L
        try {
            resolver.query(
                uri,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                    DocumentsContract.Document.COLUMN_LAST_MODIFIED,
                ),
                null, null, null,
            )?.use { c ->
                if (c.moveToFirst()) {
                    name = c.getString(0) ?: name
                    modified = if (c.isNull(1)) 0L else c.getLong(1)
                }
            }
        } catch (e: Exception) {
            return null
        }
        // One subfolder per document, so two files with the same name in
        // different folders never overwrite each other.
        val dir = File(activity.cacheDir, "doc_folder/${uri.toString().hashCode().toUInt()}")
        dir.mkdirs()
        val target = File(dir, File(name).name)
        return try {
            resolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { input.copyTo(it) }
            } ?: return null
            // The receiver keeps "Date modified" (project_mtime_preservation).
            if (modified > 0) target.setLastModified(modified)
            target.absolutePath
        } catch (e: Exception) {
            target.delete()
            null
        }
    }

    private fun <T> background(result: MethodChannel.Result, work: () -> T) {
        Thread {
            val value = try {
                work()
            } catch (e: Exception) {
                null
            }
            main.post { result.success(value) }
        }.start()
    }

    private companion object {
        const val REQUEST = 0x4446 // "DF"
        const val KEY = "tree"
        const val MAX_DEPTH = 4
        const val MAX_FILES = 3000
    }
}
