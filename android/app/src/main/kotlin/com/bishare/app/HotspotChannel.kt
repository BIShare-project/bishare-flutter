package com.bishare.app

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.net.wifi.WifiNetworkSpecifier
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/// "Hotspot" and "Wi-Fi" on the Send tab (lib/core/network/hotspot_channel.dart).
///
/// start/stop: a local-only hotspot of this phone, whose name and password go
/// into the QR code. It carries no internet and ends with the app.
///
/// join/leave: join the hotspot a scanned QR code names (Android 10+). The
/// system asks once; the network then belongs to this app only, so the process
/// is bound to it for as long as it lasts, or no socket would use it.
class HotspotChannel(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "app.bishare/hotspot")
    private val main = Handler(Looper.getMainLooper())
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var joined: ConnectivityManager.NetworkCallback? = null

    private val wifi get() =
        context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
    private val connectivity get() =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> start(result)
                "stop" -> {
                    stop()
                    result.success(null)
                }
                "join" -> join(
                    call.argument<String>("ssid").orEmpty(),
                    call.argument<String>("pass").orEmpty(),
                    result,
                )
                "leave" -> {
                    leave()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        stop()
        leave()
        channel.setMethodCallHandler(null)
    }

    private fun start(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", null, null)
            return
        }
        reservation?.let {
            result.success(describe(it))
            return
        }
        var answered = false
        try {
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(r: WifiManager.LocalOnlyHotspotReservation) {
                    reservation = r
                    if (!answered) {
                        answered = true
                        result.success(describe(r))
                    }
                }

                override fun onStopped() {
                    reservation = null
                    channel.invokeMethod("stopped", null)
                }

                override fun onFailed(reason: Int) {
                    if (!answered) {
                        answered = true
                        result.error("failed", "reason $reason", null)
                    }
                }
            }, main)
        } catch (e: SecurityException) {
            // No Nearby devices permission (13+) or no location (before).
            result.error("permission", e.message, null)
        } catch (e: IllegalStateException) {
            // Another request of this app is still active.
            result.error("failed", e.message, null)
        }
    }

    private fun stop() {
        reservation?.close()
        reservation = null
    }

    @Suppress("DEPRECATION")
    private fun describe(r: WifiManager.LocalOnlyHotspotReservation): Map<String, String> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val config = r.softApConfiguration
            val ssid = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // "name" in quotes when it is text.
                config.wifiSsid?.toString()?.removeSurrounding("\"")
            } else {
                config.ssid
            }
            return mapOf("ssid" to ssid.orEmpty(), "pass" to config.passphrase.orEmpty())
        }
        val config = r.wifiConfiguration
        return mapOf(
            "ssid" to config?.SSID.orEmpty().removeSurrounding("\""),
            "pass" to config?.preSharedKey.orEmpty().removeSurrounding("\""),
        )
    }

    private fun join(ssid: String, pass: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || ssid.isEmpty()) {
            result.error("unsupported", null, null)
            return
        }
        leave()
        val specifier = WifiNetworkSpecifier.Builder().setSsid(ssid).apply {
            if (pass.isNotEmpty()) setWpa2Passphrase(pass)
        }.build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier)
            .build()
        var answered = false
        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                connectivity.bindProcessToNetwork(network)
                main.post {
                    if (!answered) {
                        answered = true
                        result.success(true)
                    }
                }
            }

            override fun onUnavailable() {
                main.post {
                    if (joined === this) joined = null
                    if (!answered) {
                        answered = true
                        result.success(false)
                    }
                }
            }

            override fun onLost(network: Network) {
                main.post {
                    if (joined === this) {
                        leave()
                        channel.invokeMethod("left", null)
                    }
                }
            }
        }
        joined = callback
        try {
            connectivity.requestNetwork(request, callback, 60_000)
        } catch (e: SecurityException) {
            joined = null
            result.error("permission", e.message, null)
        }
    }

    private fun leave() {
        val callback = joined ?: return
        joined = null
        connectivity.bindProcessToNetwork(null)
        try {
            connectivity.unregisterNetworkCallback(callback)
        } catch (_: IllegalArgumentException) {
            // Already gone.
        }
    }
}
