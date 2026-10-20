package com.hadithly.app

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException
import java.util.UUID

/** Debug-only, permission-protected provider for real export URI rollback checks. */
class LibraryExportVerificationProvider : DocumentsProvider() {
    private val directory: File get() = File(requireNotNull(context).cacheDir, "VerificationExports").apply { mkdirs() }
    private fun file(id: String): File {
        val parsed = try { UUID.fromString(id) } catch (_: IllegalArgumentException) { throw FileNotFoundException() }
        if (parsed.toString() != id) throw FileNotFoundException()
        return File(directory, id)
    }
    override fun onCreate() = true
    override fun queryRoots(projection: Array<out String>?): Cursor {
        val result = MatrixCursor(projection ?: arrayOf(Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE, Root.COLUMN_FLAGS, Root.COLUMN_MIME_TYPES))
        val row = result.newRow()
        for (column in result.columnNames) row.add(when (column) {
            Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID -> "root"
            Root.COLUMN_TITLE -> "Export verification"
            Root.COLUMN_FLAGS -> Root.FLAG_SUPPORTS_CREATE
            Root.COLUMN_MIME_TYPES -> "application/json"
            else -> null
        })
        return result
    }
    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val result = MatrixCursor(projection ?: arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS, Document.COLUMN_SIZE))
        addRow(result, documentId)
        return result
    }
    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor {
        if (parentDocumentId != "root") throw FileNotFoundException()
        val result = MatrixCursor(projection ?: arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS, Document.COLUMN_SIZE))
        directory.listFiles().orEmpty().forEach { addRow(result, it.name) }
        return result
    }
    private fun addRow(result: MatrixCursor, id: String) {
        val root = id == "root"
        val item = if (root) directory else file(id)
        if (!item.exists()) throw FileNotFoundException()
        val row = result.newRow()
        for (column in result.columnNames) row.add(when (column) {
            Document.COLUMN_DOCUMENT_ID -> id
            Document.COLUMN_DISPLAY_NAME -> if (root) "Exports" else "$id.json"
            Document.COLUMN_MIME_TYPE -> if (root) Document.MIME_TYPE_DIR else "application/json"
            Document.COLUMN_FLAGS -> if (root) Document.FLAG_DIR_SUPPORTS_CREATE else Document.FLAG_SUPPORTS_WRITE or Document.FLAG_SUPPORTS_DELETE
            Document.COLUMN_SIZE -> if (root) 0 else item.length()
            else -> null
        })
    }
    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
        if (parentDocumentId != "root" || mimeType != "application/json") throw FileNotFoundException()
        return UUID.randomUUID().toString().also { if (!file(it).createNewFile()) throw FileNotFoundException() }
    }
    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor =
        ParcelFileDescriptor.open(file(documentId).also { if (!it.exists()) throw FileNotFoundException() }, ParcelFileDescriptor.parseMode(mode))
    override fun deleteDocument(documentId: String) { if (!file(documentId).delete()) throw FileNotFoundException() }
}
