package com.continuity.android

import android.content.Context
import android.content.Intent
import android.util.Log
import com.journeyapps.barcodescanner.BarcodeCallback
import com.journeyapps.barcodescanner.BarcodeResult
import com.journeyapps.barcodescanner.DecoratedBarcodeView
import com.journeyapps.barcodescanner.DefaultDecoderFactory
import com.google.zxing.BarcodeFormat

private const val SCANNER_TAG = "MacQrScannerView"

class MacQrScannerView(
    context: Context,
    private val onScanned: (String) -> Unit
) : DecoratedBarcodeView(context) {

    private var started = false
    private var scannerConfigured = false

    init {
        // Initialize with an empty intent to avoid NPE in the library
        initializeFromIntent(Intent())
        // Set to QR code only for better performance
        barcodeView.decoderFactory = DefaultDecoderFactory(listOf(BarcodeFormat.QR_CODE))
        // Hide the default status text
        setStatusText("")
    }

    fun startScanning() {
        Log.d(SCANNER_TAG, "startScanning() called")
        started = true

        if (!scannerConfigured) {
            Log.d(SCANNER_TAG, "Configuring scanner callback")
            decodeContinuous(object : BarcodeCallback {
                override fun barcodeResult(result: BarcodeResult?) {
                    val raw = result?.text?.trim().orEmpty()
                    if (raw.isEmpty()) return
                    Log.d(SCANNER_TAG, "QR Scanned: $raw")
                    pause()
                    onScanned(raw)
                }

                override fun possibleResultPoints(resultPoints: MutableList<com.google.zxing.ResultPoint>) = Unit
            })
            scannerConfigured = true
        }

        resume()
    }

    fun stopScanning() {
        Log.d(SCANNER_TAG, "stopScanning() called")
        started = false
        try {
            pause()
        } catch (e: Exception) {
            Log.w(SCANNER_TAG, "Stop scanner failed: ${e.message}")
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        Log.d(SCANNER_TAG, "onAttachedToWindow(), started=$started")
        if (started) {
            // Delay resume slightly to ensure surface is ready
            post {
                if (started) {
                    resume()
                }
            }
        }
    }

    override fun onDetachedFromWindow() {
        Log.d(SCANNER_TAG, "onDetachedFromWindow()")
        try {
            pause()
        } catch (e: Exception) {
            Log.w(SCANNER_TAG, "Detach scanner failed: ${e.message}")
        }
        super.onDetachedFromWindow()
    }
}
