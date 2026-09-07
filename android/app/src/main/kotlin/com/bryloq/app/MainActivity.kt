package com.bryloq.app

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    private val shareChannelName = "com.bryloq.app/share"

    private var shareChannel: MethodChannel? = null
    private var pendingShare: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        shareChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            shareChannelName
        )

        shareChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialShare" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }

                "readSharedUri" -> {
                    val uriValue = call.argument<String>("uri")

                    if (uriValue.isNullOrBlank()) {
                        result.error(
                            "INVALID_URI",
                            "The shared file URI is missing.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    try {
                        result.success(
                            readUriBytes(Uri.parse(uriValue))
                        )
                    } catch (error: Exception) {
                        result.error(
                            "READ_FAILED",
                            error.message ?: "Could not read the shared file.",
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureShareIntent(intent, notifyFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureShareIntent(intent, notifyFlutter = true)
    }

    private fun captureShareIntent(
        incomingIntent: Intent?,
        notifyFlutter: Boolean
    ) {
        if (incomingIntent == null) {
            return
        }

        val action = incomingIntent.action

        if (
            action != Intent.ACTION_SEND &&
            action != Intent.ACTION_SEND_MULTIPLE
        ) {
            return
        }

        val text = buildSharedText(incomingIntent)
        val streamUri = firstSharedUri(incomingIntent)
        val mimeType = incomingIntent.type

        val payload = if (streamUri != null) {
            mapOf(
                "kind" to "file",
                "uri" to streamUri.toString(),
                "mimeType" to (
                    contentResolver.getType(streamUri)
                        ?: mimeType
                        ?: "application/octet-stream"
                    ),
                "fileName" to queryDisplayName(streamUri),
                "text" to text
            )
        } else if (!text.isNullOrBlank()) {
            mapOf(
                "kind" to "text",
                "text" to text,
                "mimeType" to (mimeType ?: "text/plain")
            )
        } else {
            null
        }

        if (payload == null) {
            return
        }

        pendingShare = payload

        if (notifyFlutter) {
            shareChannel?.invokeMethod(
                "sharedContent",
                pendingShare
            )

            pendingShare = null
        }

        incomingIntent.action = null
    }

    private fun buildSharedText(intent: Intent): String? {
        val subject =
            intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()

        val text =
            intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()

        return when {
            !subject.isNullOrBlank() &&
                !text.isNullOrBlank() ->
                "$subject\n$text"

            !text.isNullOrBlank() ->
                text

            !subject.isNullOrBlank() ->
                subject

            else ->
                null
        }
    }

    @Suppress("DEPRECATION")
    private fun firstSharedUri(intent: Intent): Uri? {
        return if (
            intent.action == Intent.ACTION_SEND_MULTIPLE
        ) {
            intent
                .getParcelableArrayListExtra<Uri>(
                    Intent.EXTRA_STREAM
                )
                ?.firstOrNull()
        } else {
            intent.getParcelableExtra(
                Intent.EXTRA_STREAM
            )
        }
    }

    private fun queryDisplayName(uri: Uri): String {
        try {
            contentResolver.query(
                uri,
                arrayOf(OpenableColumns.DISPLAY_NAME),
                null,
                null,
                null
            )?.use { cursor ->
                val index =
                    cursor.getColumnIndex(
                        OpenableColumns.DISPLAY_NAME
                    )

                if (
                    index >= 0 &&
                    cursor.moveToFirst()
                ) {
                    val value =
                        cursor.getString(index)

                    if (!value.isNullOrBlank()) {
                        return value
                    }
                }
            }
        } catch (_: Exception) {
            // Fall back to URI path.
        }

        return uri.lastPathSegment
            ?: "shared-file"
    }

    private fun readUriBytes(uri: Uri): ByteArray {
        val input =
            contentResolver.openInputStream(uri)
                ?: throw IllegalArgumentException(
                    "Could not open the shared file."
                )

        val maximumBytes =
            20 * 1024 * 1024

        val buffer =
            ByteArray(8192)

        val output =
            ByteArrayOutputStream()

        var total = 0

        input.use { stream ->
            while (true) {
                val read =
                    stream.read(buffer)

                if (read <= 0) {
                    break
                }

                total += read

                if (total > maximumBytes) {
                    throw IllegalArgumentException(
                        "Shared files larger than 20 MB are not supported yet."
                    )
                }

                output.write(
                    buffer,
                    0,
                    read
                )
            }
        }

        return output.toByteArray()
    }
}