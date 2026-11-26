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
import android.media.MediaRecorder
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import androidx.core.content.ContextCompat
import java.io.File
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Graba EXCLUSIVAMENTE el Monitor EN VIVO (cuadro rojo) a 16:9 completo + micrófono
 * sin usar MediaProjection (cero avisos de "Compartir pantalla" y cero notificaciones),
 * y guarda el MP4 directamente en la Galería (Movies/NenoCam Studio).
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

    private var mediaRecorder: MediaRecorder? = null
    private var framePump: ProgramCanvasCapture.FramePump? = null
    private var tempOutputFile: File? = null
    private var outputFileName: String = ""
    private val mainHandler = Handler(Looper.getMainLooper())

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
            cleanupHardware()

            val hasMicPermission = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.RECORD_AUDIO,
            ) == PackageManager.PERMISSION_GRANTED
            val useAudio = audioEnabled && hasMicPermission

            val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            outputFileName = "NenoCam_$stamp.mp4"
            val cacheFile = File(cacheDir, outputFileName)
            tempOutputFile = cacheFile

            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            if (useAudio) {
                recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            }
            recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            if (useAudio) {
                recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                recorder.setAudioEncodingBitRate(128_000)
                recorder.setAudioSamplingRate(44100)
            }
            recorder.setVideoEncodingBitRate(bitrate)
            recorder.setVideoFrameRate(25)
            recorder.setVideoSize(width, height)
            recorder.setOutputFile(cacheFile.absolutePath)
            recorder.prepare()

            val surface = recorder.surface
            recorder.start()
            mediaRecorder = recorder

            val pump = ProgramCanvasCapture.FramePump(
                targetSurface = surface,
                outWidth = width,
                outHeight = height,
                fps = 25,
            )
            framePump = pump
            isRecording = true
            pump.start()

            eventCallback?.invoke("started", outputFileName)
        } catch (e: Exception) {
            isRecording = false
            cleanupHardware()
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
        framePump?.stop()
        framePump = null

        try {
            mediaRecorder?.stop()
        } catch (_: Exception) {
        }
        cleanupHardware()

        val fileToSave = tempOutputFile
        val fileName = outputFileName.ifEmpty { "NenoCam_${System.currentTimeMillis()}.mp4" }
        tempOutputFile = null

        if (fileToSave == null || !fileToSave.exists() || fileToSave.length() <= 0L) {
            eventCallback?.invoke("error", "La grabación era demasiado corta para guardarse.")
            finishService()
            return
        }

        Thread {
            try {
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

    private fun cleanupHardware() {
        framePump?.stop()
        framePump = null

        try {
            mediaRecorder?.reset()
            mediaRecorder?.release()
        } catch (_: Exception) {
        }
        mediaRecorder = null
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
        cleanupHardware()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
