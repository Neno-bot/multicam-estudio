package com.multicam.studio.multicam_studio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.pedro.common.ConnectChecker
import com.pedro.library.rtmp.RtmpDisplay

class RtmpStreamService : Service(), ConnectChecker {

    companion object {
        const val ACTION_START = "com.nenocam.studio.ACTION_START_RTMP"
        const val ACTION_STOP = "com.nenocam.studio.ACTION_STOP_RTMP"
        const val EXTRA_URL = "rtmp_url"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"
        const val EXTRA_BITRATE = "bitrate"
        const val EXTRA_AUDIO_ENABLED = "audio_enabled"

        private const val CHANNEL_ID = "nenocam_rtmp_channel"
        private const val NOTIFICATION_ID = 4201

        @Volatile
        var isLiveStreaming: Boolean = false

        @Volatile
        var eventCallback: ((String, String) -> Unit)? = null
    }

    private var rtmpDisplay: RtmpDisplay? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val url = intent.getStringExtra(EXTRA_URL) ?: return START_NOT_STICKY
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, -1)
                val resultData: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(EXTRA_RESULT_DATA)
                }
                val bitrate = intent.getIntExtra(EXTRA_BITRATE, 2500 * 1024)
                val audioEnabled = intent.getBooleanExtra(EXTRA_AUDIO_ENABLED, true)

                startForegroundWithTypes(audioEnabled)

                if (resultData == null) {
                    eventCallback?.invoke("error", "Permiso de captura de pantalla cancelado.")
                    stopSelf()
                    return START_NOT_STICKY
                }

                startRtmpBroadcast(url, resultCode, resultData, bitrate, audioEnabled)
            }

            ACTION_STOP -> {
                stopRtmpBroadcast()
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun startForegroundWithTypes(audioEnabled: Boolean) {
        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val serviceType = if (audioEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            }
            startForeground(NOTIFICATION_ID, notification, serviceType)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startRtmpBroadcast(
        url: String,
        resultCode: Int,
        resultData: Intent,
        bitrate: Int,
        audioEnabled: Boolean,
    ) {
        try {
            stopRtmpBroadcast()
            val display = RtmpDisplay(applicationContext, true, this)
            display.setIntentResult(resultCode, resultData)

            val dpi = resources.displayMetrics.densityDpi
            val videoOk = display.prepareVideo(1280, 720, 30, bitrate, 0, dpi)
            val audioOk = if (audioEnabled) {
                display.prepareAudio(128 * 1024, 44100, true, true, true)
            } else {
                true
            }

            if (videoOk && audioOk) {
                rtmpDisplay = display
                isLiveStreaming = true
                eventCallback?.invoke("connecting", "Conectando a servidor RTMP...")
                display.startStream(url)
            } else {
                isLiveStreaming = false
                eventCallback?.invoke(
                    "error",
                    "No se pudo iniciar el codificador de video/audio en este dispositivo."
                )
                stopSelf()
            }
        } catch (e: Exception) {
            isLiveStreaming = false
            eventCallback?.invoke("error", e.message ?: "Error al iniciar RTMP")
            stopSelf()
        }
    }

    private fun stopRtmpBroadcast() {
        try {
            if (rtmpDisplay?.isStreaming() == true) {
                rtmpDisplay?.stopStream()
            }
        } catch (_: Exception) {
        }
        rtmpDisplay = null
        isLiveStreaming = false
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "NenoCam Studio En Vivo",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Transmisión en vivo hacia YouTube / Facebook Live"
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("NenoCam Studio EN VIVO")
            .setContentText("Transmitiendo producción multicámara por RTMP...")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setOngoing(true)
            .build()
    }

    override fun onConnectionStarted(url: String) {
        eventCallback?.invoke("connecting", "Conectando...")
    }

    override fun onConnectionSuccess() {
        isLiveStreaming = true
        eventCallback?.invoke("connected", "EN VIVO")
    }

    override fun onConnectionFailed(reason: String) {
        isLiveStreaming = false
        stopRtmpBroadcast()
        eventCallback?.invoke("error", "Falló la conexión RTMP: $reason")
        stopSelf()
    }

    override fun onNewBitrate(bitrate: Long) {
        eventCallback?.invoke("bitrate", (bitrate / 1024).toString())
    }

    override fun onDisconnect() {
        isLiveStreaming = false
        eventCallback?.invoke("disconnected", "Transmisión finalizada")
    }

    override fun onAuthError() {
        isLiveStreaming = false
        stopRtmpBroadcast()
        eventCallback?.invoke("error", "Clave de transmisión inválida (Auth Error)")
        stopSelf()
    }

    override fun onAuthSuccess() {
        eventCallback?.invoke("connecting", "Autenticado correctamente")
    }

    override fun onDestroy() {
        stopRtmpBroadcast()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
