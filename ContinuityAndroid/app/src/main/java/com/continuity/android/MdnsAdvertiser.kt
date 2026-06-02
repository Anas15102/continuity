package com.continuity.android

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log

private const val TAG = "MdnsAdvertiser"

/**
 * Advertises "_continuity._tcp." on the local network via Android NSD (mDNS).
 * The Mac's DeviceDiscovery browses for this service and connects automatically.
 *
 * Service port matches ConnectionManager.PORT (9876).
 */
class MdnsAdvertiser(private val context: Context) {

    private val SERVICE_TYPE = "_continuity._tcp."
    private val SERVICE_NAME = "ContinuityAndroid"

    private var nsdManager: NsdManager? = null
    private var registrationListener: NsdManager.RegistrationListener? = null
    private var registeredName = ""

    fun start() {
        nsdManager = context.getSystemService(Context.NSD_SERVICE) as NsdManager

        val serviceInfo = NsdServiceInfo().apply {
            serviceName = SERVICE_NAME
            serviceType = SERVICE_TYPE
            port = ConnectionManager.PORT
        }

        registrationListener = object : NsdManager.RegistrationListener {
            override fun onServiceRegistered(info: NsdServiceInfo) {
                registeredName = info.serviceName
                Log.i(TAG, "Registered: ${info.serviceName} on port ${info.port}")
            }
            override fun onRegistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.e(TAG, "Registration failed: $errorCode")
            }
            override fun onServiceUnregistered(info: NsdServiceInfo) {
                Log.i(TAG, "Unregistered: ${info.serviceName}")
            }
            override fun onUnregistrationFailed(info: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "Unregistration failed: $errorCode")
            }
        }

        nsdManager?.registerService(serviceInfo, NsdManager.PROTOCOL_DNS_SD, registrationListener)
    }

    fun stop() {
        registrationListener?.let {
            try { nsdManager?.unregisterService(it) } catch (e: Exception) { /* ignore */ }
        }
        registrationListener = null
    }
}
