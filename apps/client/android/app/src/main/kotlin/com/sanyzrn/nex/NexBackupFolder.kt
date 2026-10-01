package com.sanyzrn.nex

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File

/**
 * A folder the person picked for automatic backups (W1.6).
 *
 * Any folder Android's own picker can open: on the phone, or one a cloud or
 * sync app exposes (Google Drive, Nextcloud, Syncthing). Nex keeps the
 * permission across restarts and writes one encrypted complete backup into
 * it at a time, keeping the newest few of its own and never touching
 * anything else there.
 */
object NexBackupFolder {
    const val REQUEST = 9912

    /** Nex's own files in the folder, and nothing else, are pruned. */
    private const val PREFIX = "Nex-auto-"
    private const val SUFFIX = ".nexfull"

    fun pickIntent(): Intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
        Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
    )

    /** Keeps the grant for [tree] and says what the folder is called. */
    fun keep(context: Context, tree: Uri): Map<String, String>? {
        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        runCatching { context.contentResolver.takePersistableUriPermission(tree, flags) }
            .onFailure { return null }
        return mapOf("uri" to tree.toString(), "name" to (nameOf(context, tree) ?: ""))
    }

    /** Whether Nex can still write to [tree] — the grant can be revoked. */
    fun reachable(context: Context, tree: Uri): Boolean =
        context.contentResolver.persistedUriPermissions.any {
            it.uri == tree && it.isWritePermission
        }

    fun release(context: Context, tree: Uri) {
        runCatching {
            context.contentResolver.releasePersistableUriPermission(
                tree,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }
    }

    /**
     * Copies [source] into [tree] as [name], then keeps only the newest [keep]
     * of Nex's own backups there. Returns null when the copy landed, or what
     * went wrong, in words Settings and the diagnostics log can show.
     *
     * Written under a temporary name and renamed when complete, so a copy cut
     * short — the phone dies, the provider fails — never leaves a file that
     * looks like a whole backup. Not every provider can rename a document
     * (cloud providers often cannot), so when the rename is refused the copy
     * is written again straight under its final name: a folder that cannot
     * rename still gets its backup.
     */
    fun copyInto(context: Context, tree: Uri, source: File, name: String, keep: Int): String? {
        val resolver = context.contentResolver
        val parent = runCatching {
            DocumentsContract.buildDocumentUriUsingTree(
                tree,
                DocumentsContract.getTreeDocumentId(tree),
            )
        }.getOrElse { return "folder: ${it.javaClass.simpleName}" }
        if (!source.exists()) return "no backup file"

        val staged = write(context, parent, "$name.partial", source)
        if (staged.error == null) {
            val renamed = runCatching {
                DocumentsContract.renameDocument(resolver, staged.uri!!, name)
            }.getOrNull()
            if (renamed != null) {
                prune(context, tree, keep)
                return null
            }
            runCatching { DocumentsContract.deleteDocument(resolver, staged.uri!!) }
        }
        // No rename, or the staged write itself failed: write the final name.
        val direct = write(context, parent, name, source)
        if (direct.error != null) {
            return staged.error?.let { "$it; then ${direct.error}" } ?: direct.error
        }
        prune(context, tree, keep)
        return null
    }

    private class Written(val uri: Uri?, val error: String?)

    private fun write(context: Context, parent: Uri, display: String, source: File): Written {
        val resolver = context.contentResolver
        val doc = runCatching {
            DocumentsContract.createDocument(resolver, parent, "application/octet-stream", display)
        }.getOrElse { return Written(null, "create: ${it.javaClass.simpleName}") }
            ?: return Written(null, "create refused")
        return try {
            // "wt" truncates; not every provider accepts the mode.
            val out = runCatching { resolver.openOutputStream(doc, "wt") }.getOrNull()
                ?: resolver.openOutputStream(doc)
                ?: throw IllegalStateException("no stream")
            out.use { stream -> source.inputStream().use { it.copyTo(stream) } }
            Written(doc, null)
        } catch (error: Exception) {
            runCatching { DocumentsContract.deleteDocument(resolver, doc) }
            Written(null, "write: ${error.javaClass.simpleName}")
        }
    }

    private fun prune(context: Context, tree: Uri, keep: Int) {
        val resolver = context.contentResolver
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        val ours = mutableListOf<Pair<String, String>>()
        runCatching {
            resolver.query(
                children,
                arrayOf(
                    DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                    DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                ),
                null,
                null,
                null,
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getString(0) ?: continue
                    val display = cursor.getString(1) ?: continue
                    if (display.startsWith(PREFIX) && display.endsWith(SUFFIX)) {
                        ours += id to display
                    }
                }
            }
        }
        // The names carry a sortable timestamp, newest last.
        ours.sortedByDescending { it.second }.drop(keep).forEach { (id, _) ->
            runCatching {
                DocumentsContract.deleteDocument(
                    resolver,
                    DocumentsContract.buildDocumentUriUsingTree(tree, id),
                )
            }
        }
    }

    private fun nameOf(context: Context, tree: Uri): String? = runCatching {
        val doc = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            DocumentsContract.getTreeDocumentId(tree),
        )
        context.contentResolver.query(
            doc,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }
    }.getOrNull()
}
