package com.neiry.neiry_kit

/**
 * Android equivalent of Flutter's FlutterError. Carries code/message/details
 * matching the shape of `result.error(code, message, details)`.
 */
class FlutterError(
    val code: String,
    override val message: String,
    val details: Any?,
) : Exception(message)

/**
 * Decodes a JNI-encoded error string of the form `"<code>|<message>"`.
 *
 * The C layer encodes `clCError` as `"$code|$message"`. If the string does
 * not contain `|`, falls back to code `"255"` (unknown) with the full string
 * as the message.
 */
fun parseSdkError(encoded: String): FlutterError {
    val sep = encoded.indexOf('|')
    return if (sep >= 0) {
        FlutterError(encoded.substring(0, sep), encoded.substring(sep + 1), null)
    } else {
        FlutterError("255", encoded, null)
    }
}
