package com.continuity.android

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

object QRGenerator {

    /**
     * Generates a QR code bitmap for the pairing URL.
     * Format: continuity://pair?ip=X.X.X.X&port=9876&name=DeviceName
     */
    fun generate(content: String, size: Int = 512): Bitmap {
        val writer = QRCodeWriter()
        val hints = mapOf(EncodeHintType.MARGIN to 1)
        val matrix = writer.encode(content, BarcodeFormat.QR_CODE, size, size, hints)

        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.RGB_565)
        for (x in 0 until size) {
            for (y in 0 until size) {
                bitmap.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
            }
        }
        return bitmap
    }

    fun pairingUrl(ip: String, port: Int, deviceName: String): String {
        val encodedName = java.net.URLEncoder.encode(deviceName, "UTF-8")
        return "continuity://pair?ip=$ip&port=$port&name=$encodedName"
    }

    /** Parse QR from Mac side: continuity://mac-pair?id=UUID&name=MacName */
    fun parseMacPairUrl(url: String): Pair<String, String>? {
        return try {
            val uri = android.net.Uri.parse(url)
            if (uri.scheme != "continuity" || uri.host != "mac-pair") return null
            val id = uri.getQueryParameter("id") ?: return null
            val name = uri.getQueryParameter("name") ?: "Mac"
            Pair(id, name)
        } catch (e: Exception) { null }
    }
}
