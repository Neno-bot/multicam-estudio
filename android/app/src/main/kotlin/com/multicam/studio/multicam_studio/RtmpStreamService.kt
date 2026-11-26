package com.multicam.studio.multicam_studio

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.content.ContextCompat
import com.pedro.common.ConnectChecker
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.pedro.encoder.input.sources.audio.NoAudioSource
import com.pedro.library.generic.GenericStream

class RtmpStreamService : Service(), ConnectChecker {

    companion object {
        const val ACTION_START = "com.nenocam.studio.ACTION_START_RTMP"
        const val ACTION_STOP = "com.nenocam.studio.ACTION_STOP_RTMP"
        const val EXTRA_URL = "rtmp_url"
        const val EXTRA_BITRATE = "bitrate"
        const val EXTRA_AUDIO_ENABLED = "audio_enabled"

        private const val CHANNEL_ID = "nenocam_rtmp_channel"
        private const val NOTIFICATION_ID = 4201

        @Volatile
        var isLiveStreaming: Boolean = false

        @Volatile
        var eventCallback: ((String, String) -> Unit)? = null
    }

    private var genericStream: GenericStream? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val url = intent.getStringExtra(EXTRA_URL) ?: return START_NOT_STICKY
                val bitrate = intent.getIntExtra(EXTRA_BITRATE, 2500 * 1024)
                val audioEnabled = intent.getBooleanExtra(EXTRA_AUDIO_ENABLED, true)

                startForegroundWithTypes(audioEnabled)
                startRtmpBroadcast(url, bitrate, audioEnabled)
            }

            ACTION_STOP -> {
                stopRtmpBroadcast()
                finishService()
            }
        }
        return START_NOT_STICKY
    }

    private fun startForegroundWithTypes(audioEnabled: Boolean) {
        val notification = buildNotification()
        val hasMicPermission = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val serviceType = if (audioEnabled && hasMicPermission && Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            }
            startForeground(NOTIFICATION_ID, notification, serviceType)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun startRtmpBroadcast(
        url: String,
        bitrate: Int,
        audioEnabled: Boolean,
    ) {
        try {
            stopRtmpBroadcast()

            val hasMicPermission = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
            val useAudio = audioEnabled && hasMicPermission

            val videoSource = ProgramCanvasVideoSource()
            val audioSource = if (useAudio) MicrophoneSource() else NoAudioSource()
            val stream = GenericStream(applicationContext, this, videoSource, audioSource)
            stream.getGlInterface().setForceRender(true, 25)

            val videoOk = stream.prepareVideo(1280, 720, bitrate, 25, 2, 0)
            val audioOk = if (useAudio) {
                stream.prepareAudio(44100, true, 128 * 1024)
            } else {
                true
            }

            if (videoOk && audioOk) {
                genericStream = stream
                isLiveStreaming = true
                eventCallback?.invoke("connecting", "Conectando a servidor RTMP...")
                stream.startStream(url)
            } else {
                isLiveStreaming = false
                eventCallback?.invoke(
                    "error",
                    "No se pudo iniciar el codificador de video/audio en este dispositivo.",
                )
                finishService()
            }
        } catch (e: Exception) {
            isLiveStreaming = false
            eventCallback?.invoke("error", e.message ?: "Error al iniciar RTMP")
            finishService()
        }
    }

    private fun stopRtmpBroadcast() {
        try {
            if (genericStream?.isStreaming == true) {
                genericStream?.stopStream()
            }
            genericStream?.release()
        } catch (_: Exception) {
        }
        genericStream = null
        isLiveStreaming = false
    }

    private fun finishService() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "NenoCam Studio En Vivo",
                NotificationManager.IMPORTANCE_LOW,
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
            .setContentText("Transmitiendo monitor de programa limpio por RTMP...")
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
        finishService()
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
        finishService()
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
