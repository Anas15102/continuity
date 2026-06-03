package com.continuity.android

import android.content.Context
import android.util.Base64
import android.util.Log
import java.io.File
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.Date
import javax.net.ssl.*
import org.bouncycastle.asn1.x500.X500Name
import org.bouncycastle.cert.jcajce.JcaX509CertificateConverter
import org.bouncycastle.cert.jcajce.JcaX509v3CertificateBuilder
import org.bouncycastle.operator.jcajce.JcaContentSignerBuilder

private const val TAG = "TLSManager"
private const val KEYSTORE_FILE = "continuity.keystore"
private const val KEYSTORE_PASS = "continuity_tls"
private const val ALIAS = "continuity"

/**
 * Generates and manages a self-signed TLS certificate for the Android TCP server.
 * The certificate fingerprint is embedded in the QR code so the Mac can verify it.
 *
 * On first run: generates RSA key pair + self-signed cert, saves to keystore file.
 * On subsequent runs: loads existing keystore.
 */
object TLSManager {

    private var sslContext: SSLContext? = null
    var certFingerprint: String = ""
        private set

    fun init(context: Context) {
        val keystoreFile = File(context.filesDir, KEYSTORE_FILE)
        val keyStore = KeyStore.getInstance("PKCS12")

        if (keystoreFile.exists()) {
            // Load existing
            keystoreFile.inputStream().use {
                keyStore.load(it, KEYSTORE_PASS.toCharArray())
            }
            Log.i(TAG, "Loaded existing keystore.")
        } else {
            // Generate new key pair + self-signed cert
            keyStore.load(null, null)
            val keyPairGen = KeyPairGenerator.getInstance("RSA")
            keyPairGen.initialize(2048, SecureRandom())
            val keyPair = keyPairGen.generateKeyPair()

            val name = X500Name("CN=Continuity,O=Continuity,C=US")
            val serial = BigInteger.valueOf(System.currentTimeMillis())
            val notBefore = Date()
            val notAfter = Date(System.currentTimeMillis() + 10L * 365 * 24 * 3600 * 1000) // 10 years

            val certBuilder = JcaX509v3CertificateBuilder(
                name, serial, notBefore, notAfter, name, keyPair.public
            )
            val signer = JcaContentSignerBuilder("SHA256withRSA").build(keyPair.private)
            val cert = JcaX509CertificateConverter().getCertificate(certBuilder.build(signer))

            keyStore.setKeyEntry(ALIAS, keyPair.private, KEYSTORE_PASS.toCharArray(), arrayOf(cert))

            keystoreFile.outputStream().use {
                keyStore.store(it, KEYSTORE_PASS.toCharArray())
            }
            Log.i(TAG, "Generated new TLS certificate.")
        }

        // Extract fingerprint
        val cert = keyStore.getCertificate(ALIAS) as X509Certificate
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        val fp = digest.digest(cert.encoded)
        certFingerprint = fp.joinToString(":") { "%02X".format(it) }
        Log.i(TAG, "Cert fingerprint: ${certFingerprint.take(20)}...")

        // Build SSLContext
        val kmf = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm())
        kmf.init(keyStore, KEYSTORE_PASS.toCharArray())

        // Trust manager that accepts all certs from the Mac (also self-signed)
        val trustAll = arrayOf<TrustManager>(object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<X509Certificate>, authType: String) {}
            override fun checkServerTrusted(chain: Array<X509Certificate>, authType: String) {}
            override fun getAcceptedIssuers(): Array<X509Certificate> = arrayOf()
        })

        val ctx = SSLContext.getInstance("TLS")
        ctx.init(kmf.keyManagers, trustAll, SecureRandom())
        sslContext = ctx
    }

    fun serverSocketFactory(): SSLServerSocketFactory =
        sslContext?.serverSocketFactory ?: throw IllegalStateException("TLSManager not initialized")
}
