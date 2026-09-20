package com.rtlsdrmobile.rtlsdr_mobile

import android.Manifest
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Todo o ciclo de vida USB (detecção, permissão, abertura do driver nativo
 * via JNI, MediaStore/Downloads, share sheet) é do plugin
 * `driver_rtlsdr` (canais `driver_rtlsdr` e `driver_rtlsdr/events`,
 * registrado automaticamente pelo GeneratedPluginRegistrant) — o pacote
 * deliberadamente não gerencia foreground service, então o que sobra aqui
 * é só o canal próprio do app pra iniciar/parar o [StreamingService].
 */
class MainActivity : FlutterActivity() {

    private var usbDetachReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startForegroundService" -> {
                        startStreamingService()
                        result.success(null)
                    }
                    "stopForegroundService" -> {
                        stopStreamingService()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        registerUsbDetachReceiver()
        requestNotificationPermissionIfNeeded()
    }

    override fun onDestroy() {
        usbDetachReceiver?.let {
            unregisterReceiver(it)
            usbDetachReceiver = null
        }
        super.onDestroy()
    }

    private fun startStreamingService() {
        val intent = Intent(this, StreamingService::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    private fun stopStreamingService() {
        stopService(Intent(this, StreamingService::class.java))
    }

    /**
     * Defensivo: se o dongle for desconectado no meio do streaming, o
     * RadioController.dart pode não ter chance de mandar
     * stopForegroundService — garante que não fique um foreground service
     * travado sem dispositivo nenhum por trás. (Antes isso vivia no
     * UsbBridge.kt do app, que foi substituído pelo plugin; o plugin fecha
     * o driver nativo no detach, mas não conhece o service do app.)
     */
    private fun registerUsbDetachReceiver() {
        if (usbDetachReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action == UsbManager.ACTION_USB_DEVICE_DETACHED) {
                    stopStreamingService()
                }
            }
        }
        val filter = IntentFilter(UsbManager.ACTION_USB_DEVICE_DETACHED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(receiver, filter)
        }
        usbDetachReceiver = receiver
    }

    private fun requestNotificationPermissionIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val granted = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        if (!granted) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "rtlsdr/usb"
    }
}
