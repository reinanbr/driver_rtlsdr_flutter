package com.rtlsdrmobile.driver_rtlsdr

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager

/**
 * Recebe os broadcasts do sistema Android relacionados ao ciclo de vida do
 * USB (plug/unplug) e o resultado do diálogo de permissão que
 * [DriverRtlsdrPlugin] dispara via PendingIntent com a action
 * [actionUsbPermission].
 */
class UsbAttachReceiver(
    private val actionUsbPermission: String,
    private val listener: Listener,
) : BroadcastReceiver() {

    interface Listener {
        fun onDeviceAttached(device: UsbDevice)
        fun onDeviceDetached(device: UsbDevice)
        fun onPermissionResult(device: UsbDevice, granted: Boolean)
    }

    override fun onReceive(context: Context, intent: Intent) {
        val device: UsbDevice = extractDevice(intent) ?: return

        when (intent.action) {
            UsbManager.ACTION_USB_DEVICE_ATTACHED -> listener.onDeviceAttached(device)
            UsbManager.ACTION_USB_DEVICE_DETACHED -> listener.onDeviceDetached(device)
            actionUsbPermission -> {
                val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                listener.onPermissionResult(device, granted)
            }
        }
    }

    private fun extractDevice(intent: Intent): UsbDevice? {
        @Suppress("DEPRECATION")
        return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
        } else {
            intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
        }
    }
}
