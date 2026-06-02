package com.continuity.android

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {

    private val notificationPermissionLauncher = registerForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        if (granted) startService()
        else Toast.makeText(this, "Notification permission needed for full features", Toast.LENGTH_LONG).show()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

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
                    getDeviceIp = { getWifiIpAddress() }
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
    getDeviceIp: () -> String
) {
    var isRunning by remember { mutableStateOf(false) }
    var isMacConnected by remember { mutableStateOf(false) }
    var deviceIp by remember { mutableStateOf("") }

    // Poll connection state every second
    LaunchedEffect(isRunning) {
        if (isRunning) {
            deviceIp = getDeviceIp()
            while (isRunning) {
                isMacConnected = ConnectionManager.isConnected()
                delay(1000)
            }
        } else {
            isMacConnected = false
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
                    Icon(Icons.Default.Stop, contentDescription = null)
                    Spacer(modifier = Modifier.width(8.dp))
                    Text("Stop Service", fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // How to connect hint
            if (isRunning && !isMacConnected) {
                HowToConnectCard(ip = deviceIp, port = ConnectionManager.PORT)
            }
        }
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

                Text("Your phone's address", fontSize = 12.sp, color = Color.White.copy(alpha = 0.4f))
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "$deviceIp:$port",
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    fontFamily = FontFamily.Monospace,
                    color = MaterialTheme.colorScheme.primary,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "Enter this in ContinuityMac to connect",
                    fontSize = 12.sp,
                    color = Color.White.copy(alpha = 0.4f),
                    textAlign = TextAlign.Center
                )
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
                icon = Icons.Default.ContentCopy,
                label = "Clipboard Sync",
                active = isMacConnected
            )
            FeatureStatusRow(
                icon = Icons.Default.Notifications,
                label = "Notification Bridge",
                active = isMacConnected
            )
            FeatureStatusRow(
                icon = Icons.Default.Wifi,
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
fun HowToConnectCard(ip: String, port: Int) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(14.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)
        )
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(
                "How to connect",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.primary
            )
            Spacer(modifier = Modifier.height(6.dp))
            Text(
                "1. Open ContinuityMac on your Mac\n" +
                "2. Click the menu bar icon\n" +
                "3. Enter this phone's IP above\n" +
                "4. Both devices must be on the same Wi-Fi",
                fontSize = 12.sp,
                color = Color.White.copy(alpha = 0.6f),
                lineHeight = 18.sp
            )
        }
    }
}
