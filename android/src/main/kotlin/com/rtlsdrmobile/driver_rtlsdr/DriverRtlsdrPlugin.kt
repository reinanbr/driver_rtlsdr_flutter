package com.rtlsdrmobile.driver_rtlsdr

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbDeviceConnection
import android.hardware.usb.UsbManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * Core of the driver_rtlsdr plugin: detects the RTL-SDR dongle via [UsbManager],
 * requests permission, and passes the `UsbDeviceConnection` file descriptor
 * on to the native driver via JNI (`nativeOpenWithFd`) — `libnative_rtlsdr.so`,
 * which opens the dongle with `libusb_wrap_sys_device()` + `rtlsdr_open_fd()` (see
 * `android/src/main/cpp/rtlsdr_shim.c`).
 *
 * From that point on, tuning/streaming/statistics/RDS/recording are
 * controlled directly from the Dart side via FFI in the same native library (see
 * `lib/src/native_bindings.dart`) — this class only handles the lifecycle
 * of the USB permission/connection, exposed to Dart through a `MethodChannel`
 * (commands) and an `EventChannel` (attached/detached/permissionGranted/
 * permissionDenied/deviceReady/error).
 *
 * Unlike the original rtl-sdr_mobile app (from which this driver was
 * extracted into plugin form), this module does NOT manage a foreground
 * service — keeping the process alive in the background during streaming is
 * a UX decision specific to each consuming app (see README.md),
 * not the driver's responsibility.
 */
class DriverRtlsdrPlugin :
    FlutterPlugin,
    MethodCallHandler,
    EventChannel.StreamHandler,
    UsbAttachReceiver.Listener {

    private lateinit var context: Context
    private lateinit var usbManager: UsbManager
    private lateinit var actionUsbPermission: String
    private lateinit var receiver: UsbAttachReceiver

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private var receiverRegistered = false
    private var usbConnection: UsbDeviceConnection? = null

    private external fun nativeOpenWithFd(fd: Int, vendorId: Int, productId: Int): Int
    private external fun nativeClose(): Int
    private external fun nativeIsOpen(): Boolean

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        actionUsbPermission = "${context.packageName}.driver_rtlsdr.USB_PERMISSION"
        receiver = UsbAttachReceiver(actionUsbPermission, this)

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)

        startReceiver()
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        closeNativeDevice()
        stopReceiver()
    }

    private fun startReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
            addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            addAction(actionUsbPermission)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
        receiverRegistered = true
    }

    private fun stopReceiver() {
        if (!receiverRegistered) return
        context.unregisterReceiver(receiver)
        receiverRegistered = false
    }

    // ---- MethodChannel.MethodCallHandler ---------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getConnectedDevice" -> result.success(findFirstDevice()?.let { toMap(it) })
            "requestPermission" -> {
                val device = findFirstDevice()
                if (device == null) {
                    result.error("NO_DEVICE", "No USB device connected", null)
                    return
                }
                requestPermission(device)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun findFirstDevice(): UsbDevice? = usbManager.deviceList.values.firstOrNull()

    private fun requestPermission(device: UsbDevice) {
        if (usbManager.hasPermission(device)) {
            eventSink?.success(eventMap("permissionGranted", device))
            openNativeDevice(device)
            return
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            0,
            Intent(actionUsbPermission).setPackage(context.packageName),
            flags,
        )
        usbManager.requestPermission(device, pendingIntent)
    }

    // ---- EventChannel.StreamHandler --------------------------------------

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ---- UsbAttachReceiver.Listener ---------------------------------------

    override fun onDeviceAttached(device: UsbDevice) {
        Log.i(TAG, "USB device connected: ${device.deviceName} (${device.vendorId}:${device.productId})")
        eventSink?.success(eventMap("attached", device))
    }

    override fun onDeviceDetached(device: UsbDevice) {
        Log.i(TAG, "USB device disconnected: ${device.deviceName}")
        closeNativeDevice()
        eventSink?.success(mapOf("type" to "detached"))
    }

    override fun onPermissionResult(device: UsbDevice, granted: Boolean) {
        Log.i(TAG, "USB permission result for ${device.deviceName}: $granted")
        if (granted) {
            eventSink?.success(eventMap("permissionGranted", device))
            openNativeDevice(device)
        } else {
            eventSink?.success(mapOf("type" to "permissionDenied"))
        }
    }

    // ---- Native driver ----------------------------------------------------

    private fun openNativeDevice(device: UsbDevice) {
        val connection = usbManager.openDevice(device)
        if (connection == null) {
            Log.e(TAG, "usbManager.openDevice() returned null for ${device.deviceName}")
            eventSink?.success(mapOf("type" to "error", "message" to "Failed to open UsbDeviceConnection"))
            return
        }

        val status = nativeOpenWithFd(connection.fileDescriptor, device.vendorId, device.productId)
        if (status != 0) {
            Log.e(TAG, "nativeOpenWithFd failed with status $status")
            connection.close()
            eventSink?.success(
                mapOf("type" to "error", "message" to "Native driver failed to open the dongle (status $status)"),
            )
            return
        }

        usbConnection = connection
        Log.i(TAG, "Native driver opened successfully for ${device.deviceName}")
        eventSink?.success(eventMap("deviceReady", device))
    }

    private fun closeNativeDevice() {
        if (usbConnection == null) return
        if (nativeIsOpen()) {
            nativeClose()
        }
        usbConnection?.close()
        usbConnection = null
    }

    // ---- Helpers ----------------------------------------------------------

    private fun eventMap(type: String, device: UsbDevice): Map<String, Any?> =
        mapOf("type" to type, "device" to toMap(device))

    private fun toMap(device: UsbDevice): Map<String, Any?> = mapOf(
        "vendorId" to device.vendorId,
        "productId" to device.productId,
        "deviceName" to device.deviceName,
        "productName" to device.productName,
        "manufacturerName" to device.manufacturerName,
    )

    companion object {
        private const val TAG = "DriverRtlsdrPlugin"
        private const val METHOD_CHANNEL = "driver_rtlsdr"
        private const val EVENT_CHANNEL = "driver_rtlsdr/events"

        init {
            System.loadLibrary("native_rtlsdr")
        }
    }
}
