package com.multicam.studio.multicam_studio

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import com.pedro.common.ConnectChecker
import com.pedro.encoder.input.sources.audio.MicrophoneSource
import com.pedro.encoder.input.sources.audio.NoAudioSource
import com.pedro.library.base.recording.RecordController
import com.pedro.library.generic.GenericStream
import java.io.File
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Graba EXCLUSIVAMENTE el Monitor EN VIVO (cuadro rojo) usando RootEncoder GenericStream
 * (OpenGL ES + MediaCodec H.264/AAC) sin usar MediaProjection ni MediaRecorder Canvas,
 * eliminando el video negro en Samsung Exynos/Android 15, y guarda el MP4 directo en Galería.
 */
class ScreenRecordService : Service() {

    companion object {
        const val ACTION_START = "com.nenocam.studio.ACTION_START_RECORD"
        const val ACTION_STOP = "com.nenocam.studio.ACTION_STOP_RECORD"
        const val EXTRA_WIDTH = "width"
        const val EXTRA_HEIGHT = "height"
        const val EXTRA_BITRATE = "bitrate"
        const val EXTRA_AUDIO_ENABLED = "audio_enabled"

        private const val CHANNEL_ID = "nenocam_record_channel"
        private const val NOTIFICATION_ID = 4202

        @Volatile
        var isRecording: Boolean = false

        @Volatile
        var eventCallback: ((String, String) -> Unit)? = null
    }

    private var genericStream: GenericStream? = null
    private var tempOutputFile: File? = null
    private var outputFileName: String = ""
    private val mainHandler = Handler(Looper.getMainLooper())

    private val noopConnectChecker = object : ConnectChecker {
        override fun onConnectionStarted(url: String) {}
        override fun onConnectionSuccess() {}
        override fun onConnectionFailed(reason: String) {}
        override fun onNewBitrate(bitrate: Long) {}
        override fun onDisconnect() {}
        override fun onAuthError() {}
        override fun onAuthSuccess() {}
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val width = intent.getIntExtra(EXTRA_WIDTH, 1280)
                val height = intent.getIntExtra(EXTRA_HEIGHT, 720)
                val bitrate = intent.getIntExtra(EXTRA_BITRATE, 4_000_000)
                val audioEnabled = intent.getBooleanExtra(EXTRA_AUDIO_ENABLED, true)

                startForegroundWithTypes(audioEnabled)
                startProgramRecording(width, height, bitrate, audioEnabled)
            }

            ACTION_STOP -> {
                stopRecordingAndSaveToGallery()
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

    private fun startProgramRecording(
        width: Int,
        height: Int,
        bitrate: Int,
        audioEnabled: Boolean,
    ) {
        try {
            cleanupStream()

            val hasMicPermission = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
            val useAudio = audioEnabled && hasMicPermission

            val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            outputFileName = "NenoCam_$stamp.mp4"
            val cacheFile = File(cacheDir, outputFileName)
            tempOutputFile = cacheFile

            val videoSource = ProgramCanvasVideoSource()
            val audioSource = if (useAudio) MicrophoneSource() else NoAudioSource()
            val stream = GenericStream(applicationContext, noopConnectChecker, videoSource, audioSource)
            stream.getGlInterface().setForceRender(true, 25)

            val videoOk = stream.prepareVideo(width, height, bitrate, 25, 2, 0)
            val audioOk = if (useAudio) {
                stream.prepareAudio(44100, true, 128 * 1024)
            } else {
                true
            }

            if (!videoOk || !audioOk) {
                cleanupStream()
                eventCallback?.invoke("error", "No se pudo inicializar el codificador H.264/AAC.")
                finishService()
                return
            }

            genericStream = stream
            stream.startRecord(
                cacheFile.absolutePath,
                object : RecordController.Listener {
                    override fun onStatusChange(status: RecordController.Status) {
                        if (status == RecordController.Status.RECORDING) {
                            isRecording = true
                        }
                    }

                    override fun onNewBitrate(bitrate: Long) {}

                    override fun onError(e: Exception) {
                        isRecording = false
                        eventCallback?.invoke("error", e.message ?: "Error durante la grabación")
                    }
                },
            )
            isRecording = true
            eventCallback?.invoke("started", outputFileName)
        } catch (e: Exception) {
            isRecording = false
            cleanupStream()
            eventCallback?.invoke("error", e.message ?: "Error al iniciar la grabación")
            finishService()
        }
    }

    private fun stopRecordingAndSaveToGallery() {
        if (!isRecording && tempOutputFile == null) {
            finishService()
            return
        }

        isRecording = false
        cleanupStream()

        val fileToSave = tempOutputFile
        val fileName = outputFileName.ifEmpty { "NenoCam_${System.currentTimeMillis()}.mp4" }
        tempOutputFile = null

        Thread {
            try {
                // Esperar breve instante para que Android MediaMuxer cierre el encabezado MP4
                Thread.sleep(250)
                if (fileToSave == null || !fileToSave.exists() || fileToSave.length() <= 0L) {
                    eventCallback?.invoke("error", "La grabación era demasiado corta para guardarse.")
                    return@Thread
                }
                val savedLocation = publishToGallery(fileToSave, fileName)
                fileToSave.delete()
                eventCallback?.invoke("saved", savedLocation)
            } catch (e: Exception) {
                eventCallback?.invoke("error", "No se pudo guardar en Galería: ${e.message}")
            } finally {
                mainHandler.post { finishService() }
            }
        }.start()
    }

    private fun publishToGallery(sourceFile: File, fileName: String): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(
                    MediaStore.Video.Media.RELATIVE_PATH,
                    "${Environment.DIRECTORY_MOVIES}/NenoCam Studio",
                )
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("No se pudo crear el archivo en MediaStore")

            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(sourceFile).use { input ->
                    input.copyTo(out)
                }
            } ?: throw IllegalStateException("No se pudo abrir el destino en Galería")

            values.clear()
            values.put(MediaStore.Video.Media.IS_PENDING, 0)
            resolver.update(uri, values, null, null)
            return "Galería (Movies/NenoCam Studio/$fileName)"
        } else {
            @Suppress("DEPRECATION")
            val moviesDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES)
            val targetDir = File(moviesDir, "NenoCam Studio")
            if (!targetDir.exists()) {
                targetDir.mkdirs()
            }
            val destFile = File(targetDir, fileName)
            sourceFile.copyTo(destFile, overwrite = true)
            MediaScannerConnection.scanFile(
                applicationContext,
                arrayOf(destFile.absolutePath),
                arrayOf("video/mp4"),
                null,
            )
            return "Galería (${destFile.absolutePath})"
        }
    }

    private fun cleanupStream() {
        try {
            if (genericStream?.isRecording == true) {
                genericStream?.stopRecord()
            }
            genericStream?.release()
        } catch (_: Exception) {
        }
        genericStream = null
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
                "NenoCam Studio Grabación",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Grabación limpia del Monitor EN VIVO para Galería"
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
            .setContentTitle("NenoCam Studio GRABANDO")
            .setContentText("Guardando monitor limpio en MP4 para tu Galería...")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setOngoing(true)
            .build()
    }

    override fun onDestroy() {
        isRecording = false
        cleanupStream()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
