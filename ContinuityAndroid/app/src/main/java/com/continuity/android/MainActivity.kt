package com.continuity.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue

class MainActivity : ComponentActivity() {

    private var cameraPermissionGranted by mutableStateOf(false)

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startService()
        else Toast.makeText(this, "Notification permission needed for full features", Toast.LENGTH_LONG).show()
    }

    private val cameraPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        cameraPermissionGranted = granted
        if (!granted) {
            Toast.makeText(this, "Camera permission is needed to scan the Mac QR code", Toast.LENGTH_LONG).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ConnectionManager.init(applicationContext)
        cameraPermissionGranted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.CAMERA
        ) == PackageManager.PERMISSION_GRANTED

        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Color(0xFF4A9EFF),
                    background = Color(0xFF0F0F12),
                    surface = Color(0xFF1A1A22),
                    onBackground = Color.White,
                    onSurface = Color.White
                )
            ) {
                ContinuityApp(
                    onStart = { requestPermissionsAndStart() },
                    onStop = { stopContinuityService() },
                    getDeviceIp = { getWifiIpAddress() },
                    hasCameraPermission = { cameraPermissionGranted },
                    requestCameraPermission = {
                        cameraPermissionLauncher.launch(Manifest.permission.CAMERA)
                    }
                )
            }
        }
    }

    private fun requestPermissionsAndStart() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
                != PackageManager.PERMISSION_GRANTED) {
                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                return
            }
        }
        startService()
    }

    private fun startService() {
        val intent = Intent(this, ContinuityService::class.java)
        startForegroundService(intent)
    }

    private fun stopContinuityService() {
        val intent = Intent(this, ContinuityService::class.java).apply {
            action = ContinuityService.ACTION_STOP
        }
        startService(intent)
    }

    private fun getWifiIpAddress(): String {
        val wifiManager = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
        val ip = wifiManager.connectionInfo.ipAddress
        if (ip == 0) return "Not connected to Wi-Fi"
        return String.format(
            "%d.%d.%d.%d",
            ip and 0xff,
            ip shr 8 and 0xff,
            ip shr 16 and 0xff,
            ip shr 24 and 0xff
        )
    }
}

@Composable
fun ContinuityApp(
    onStart: () -> Unit,
    onStop: () -> Unit,
    getDeviceIp: () -> String,
    hasCameraPermission: () -> Boolean,
    requestCameraPermission: () -> Unit
) {
    var isRunning by remember { mutableStateOf(false) }
    var isMacConnected by remember { mutableStateOf(false) }
    var deviceIp by remember { mutableStateOf("") }
    var showScanner by remember { mutableStateOf(false) }
    val pairedMacs = remember { mutableStateListOf<ConnectionManager.PairedMac>() }
    val context = LocalContext.current

    fun refreshPairedMacs() {
        pairedMacs.clear()
        pairedMacs.addAll(ConnectionManager.getPairedMacList())
    }

    // Poll connection state every second
    LaunchedEffect(isRunning) {
        if (isRunning) {
            deviceIp = getDeviceIp()
            while (isRunning) {
                isMacConnected = ConnectionManager.isConnected()
                refreshPairedMacs()
                delay(1000)
            }
        } else {
            isMacConnected = false
            refreshPairedMacs()
        }
    }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
                .padding(horizontal = 24.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.height(48.dp))

            // Header
            Text(
                text = "Continuity",
                fontSize = 28.sp,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground
            )
            Text(
                text = "Android ↔ Mac companion",
                fontSize = 14.sp,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f),
                modifier = Modifier.padding(top = 4.dp)
            )

            Spacer(modifier = Modifier.height(40.dp))

            // Connection status pulsing indicator
            ConnectionStatusCard(
                isRunning = isRunning,
                isMacConnected = isMacConnected,
                deviceIp = deviceIp,
                port = ConnectionManager.PORT
            )

            Spacer(modifier = Modifier.height(28.dp))

            // Feature status list
            if (isRunning) {
                FeatureStatusList(isMacConnected = isMacConnected)
                Spacer(modifier = Modifier.height(28.dp))

                PairingCard(
                    isMacConnected = isMacConnected,
                    pairedMacs = pairedMacs,
                    onScanMacQr = { showScanner = true },
                    onForgetMac = { macId ->
                        ConnectionManager.removePairing(macId)
                        refreshPairedMacs()
                    }
                )

                Spacer(modifier = Modifier.height(20.dp))
            }

            // Start / Stop button
            if (!isRunning) {
                Button(
                    onClick = {
                        isRunning = true
                        onStart()
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary
                    )
                ) {
                    Icon(Icons.Default.PlayArrow, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Start Service", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            } else {
                OutlinedButton(
                    onClick = {
                        isRunning = false
                        onStop()
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(52.dp),
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = Color(0xFFFF5555)
                    ),
                    border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFFFF5555).copy(alpha = 0.5f))
                ) {
                    Icon(Icons.Default.Close, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Stop Service", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // How to connect hint
            if (isRunning && !isMacConnected) {
                HowToConnectCard()
            }
        }
    }

    if (showScanner) {
        MacQrScannerDialog(
            hasCameraPermission = hasCameraPermission(),
            onDismiss = { showScanner = false },
            onPair = { macId, macName ->
                ConnectionManager.pairMac(macId, macName)
                refreshPairedMacs()
                showScanner = false
                Toast.makeText(context, "Paired with $macName", Toast.LENGTH_SHORT).show()
            },
            onRequestPermission = requestCameraPermission
        )
    }
}

@Composable
fun ConnectionStatusCard(
    isRunning: Boolean,
    isMacConnected: Boolean,
    deviceIp: String,
    port: Int
) {
    val statusColor = when {
        isMacConnected -> Color(0xFF4CAF50)
        isRunning -> Color(0xFFFF9800)
        else -> Color(0xFF666666)
    }
    val statusText = when {
        isMacConnected -> "Mac Connected"
        isRunning -> "Waiting for Mac…"
        else -> "Service Stopped"
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(
            modifier = Modifier.padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Pulsing dot
            Box(
                modifier = Modifier
                    .size(14.dp)
                    .clip(CircleShape)
                    .background(statusColor)
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = statusText,
                fontSize = 17.sp,
                fontWeight = FontWeight.SemiBold,
                color = statusColor
            )

            if (isRunning && deviceIp.isNotEmpty()) {
                Spacer(modifier = Modifier.height(14.dp))
                Divider(color = Color.White.copy(alpha = 0.06f))
                Spacer(modifier = Modifier.height(14.dp))

                if (isMacConnected) {
                    // Connected — show minimal info
                    Text("Connected to Mac", fontSize = 13.sp, color = Color(0xFF4CAF50))
                    Text(deviceIp, fontSize = 12.sp,
                        fontFamily = FontFamily.Monospace,
                        color = Color.White.copy(alpha = 0.4f))
                } else {
                    Text("Waiting for Mac", fontSize = 12.sp, color = Color.White.copy(alpha = 0.5f))
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(
                        text = "Port $port",
                        fontSize = 13.sp,
                        fontWeight = FontWeight.Bold,
                        fontFamily = FontFamily.Monospace,
                        color = MaterialTheme.colorScheme.primary
                    )
                    Text(
                        text = "Use Scan QR below to trust a Mac",
                        fontSize = 11.sp,
                        color = Color.White.copy(alpha = 0.4f),
                        textAlign = TextAlign.Center
                    )
                }
            }
        }
    }
}

@Composable
fun PairingCard(
    isMacConnected: Boolean,
    pairedMacs: List<ConnectionManager.PairedMac>,
    onScanMacQr: () -> Unit,
    onForgetMac: (String) -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Info, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                Spacer(modifier = Modifier.width(10.dp))
                Column(modifier = Modifier.weight(1f)) {
                    Text("Pair Mac", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text(
                        if (isMacConnected) "This Mac is connected and trusted"
                        else "Scan the QR code shown in the Mac app to trust it",
                        fontSize = 12.sp,
                        color = Color.White.copy(alpha = 0.6f)
                    )
                }
                Button(
                    onClick = onScanMacQr,
                    shape = RoundedCornerShape(12.dp),
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 10.dp)
                ) {
                    Text("Scan QR")
                }
            }

            if (pairedMacs.isEmpty()) {
                Text(
                    text = "No Macs trusted yet. Open Continuity on your Mac, click Pair New Device, and scan the QR here.",
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.55f)
                )
            } else {
                Text("Trusted Macs", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Color.White.copy(alpha = 0.7f))
                pairedMacs.take(3).forEach { mac ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .background(Color.White.copy(alpha = 0.04f))
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Notifications, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                        Spacer(modifier = Modifier.width(10.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(mac.name, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                            Text(mac.id, fontSize = 10.sp, fontFamily = FontFamily.Monospace, color = Color.White.copy(alpha = 0.45f))
                        }
                        TextButton(onClick = { onForgetMac(mac.id) }) {
                            Text("Forget")
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun FeatureStatusList(isMacConnected: Boolean) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(18.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
    ) {
        Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            FeatureStatusRow(
                icon = Icons.Default.Notifications,
                label = "Clipboard Sync",
                active = isMacConnected
            )
            FeatureStatusRow(
                icon = Icons.Default.Notifications,
                label = "Notification Bridge",
                active = isMacConnected
            )
            FeatureStatusRow(
                icon = Icons.Default.Info,
                label = "mDNS Advertising",
                active = true
            )
        }
    }
}

@Composable
fun FeatureStatusRow(icon: ImageVector, label: String, active: Boolean) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            tint = if (active) MaterialTheme.colorScheme.primary else Color.Gray,
            modifier = Modifier.size(20.dp)
        )
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = label,
            fontSize = 14.sp,
            color = Color.White.copy(alpha = 0.85f),
            modifier = Modifier.weight(1f)
        )
        Box(
            modifier = Modifier
                .size(8.dp)
                .clip(CircleShape)
                .background(if (active) Color(0xFF4CAF50) else Color(0xFF444444))
        )
    }
}

@Composable
fun HowToConnectCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                "How to pair",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                "1. Open ContinuityMac on your Mac\n" +
                "2. Click the menu bar icon\n" +
                "3. Click Pair New Device\n" +
                "4. Scan the QR code shown on the Mac\n" +
                "5. Done — it auto-connects next time",
                fontSize = 12.sp,
                color = Color.White.copy(alpha = 0.6f),
                lineHeight = 18.sp
            )
        }
    }
}

@Composable
fun MacQrScannerDialog(
    hasCameraPermission: Boolean,
    onDismiss: () -> Unit,
    onPair: (String, String) -> Unit,
    onRequestPermission: () -> Unit
) {
    var scanned by remember { mutableStateOf(false) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.72f))
            .padding(24.dp)
    ) {
        Surface(
            shape = RoundedCornerShape(24.dp),
            color = MaterialTheme.colorScheme.surface,
            modifier = Modifier.align(Alignment.Center)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(18.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                    Text("Scan Mac QR", fontSize = 18.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(modifier = Modifier.weight(1f))
                    TextButton(onClick = onDismiss) { Text("Close") }
                }

                Spacer(modifier = Modifier.height(12.dp))

                Text(
                    "Point your camera at the QR code shown in Continuity on your Mac.",
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.6f),
                    textAlign = TextAlign.Center
                )

                Spacer(modifier = Modifier.height(14.dp))

                if (hasCameraPermission) {
                    var scannerView by remember { mutableStateOf<MacQrScannerView?>(null) }

                    AndroidView(
                        factory = { context ->
                            MacQrScannerView(context) { raw ->
                                if (scanned) return@MacQrScannerView
                                QRGenerator.parseMacPairUrl(raw)?.let { (macId, macName) ->
                                    scanned = true
                                    onPair(macId, macName)
                                }
                            }.apply {
                                scannerView = this
                                startScanning()
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(280.dp),
                        update = { /* no-op to avoid recomposition loop */ }
                    )

                    DisposableEffect(Unit) {
                        onDispose {
                            scannerView?.stopScanning()
                        }
                    }
                } else {
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(14.dp),
                        colors = CardDefaults.cardColors(containerColor = Color.White.copy(alpha = 0.04f))
                    ) {
                        Column(
                            modifier = Modifier.padding(16.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(Icons.Default.Info, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
                            Text("Camera permission required", fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
                            Text(
                                "Grant camera access so the app can scan the QR code shown on your Mac.",
                                fontSize = 11.sp,
                                color = Color.White.copy(alpha = 0.55f),
                                textAlign = TextAlign.Center
                            )
                            Button(onClick = onRequestPermission) {
                                Text("Allow Camera")
                            }
                        }
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                Text(
                    "If scanning fails, make sure the QR is fully visible on the Mac and the room is bright.",
                    fontSize = 11.sp,
                    color = Color.White.copy(alpha = 0.45f),
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}
