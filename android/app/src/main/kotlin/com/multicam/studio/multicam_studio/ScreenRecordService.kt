package com.multicam.studio.multicam_studio

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.MediaScannerConnection
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.MediaStore
import java.io.File
import java.io.FileInputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class ScreenRecordService : Service() {

    companion object {
        const val ACTION_START = "com.nenocam.studio.ACTION_START_RECORD"
        const val ACTION_STOP = "com.nenocam.studio.ACTION_STOP_RECORD"
        const val EXTRA_RESULT_CODE = "result_code"
        const val EXTRA_RESULT_DATA = "result_data"
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

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var mediaRecorder: MediaRecorder? = null
    private var tempOutputFile: File? = null
    private var outputFileName: String = ""
    private val mainHandler = Handler(Looper.getMainLooper())

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            if (isRecording) {
                stopRecordingAndSaveToGallery()
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, -1)
                val resultData: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(EXTRA_RESULT_DATA)
                }
                val width = intent.getIntExtra(EXTRA_WIDTH, 1280)
                val height = intent.getIntExtra(EXTRA_HEIGHT, 720)
                val bitrate = intent.getIntExtra(EXTRA_BITRATE, 4_000_000)
                val audioEnabled = intent.getBooleanExtra(EXTRA_AUDIO_ENABLED, true)

                startForegroundWithTypes(audioEnabled)

                if (resultData == null) {
                    eventCallback?.invoke("error", "Permiso de grabación cancelado.")
                    stopSelf()
                    return START_NOT_STICKY
                }

                startScreenRecording(resultCode, resultData, width, height, bitrate, audioEnabled)
            }

            ACTION_STOP -> {
                stopRecordingAndSaveToGallery()
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

    private fun startScreenRecording(
        resultCode: Int,
        resultData: Intent,
        width: Int,
        height: Int,
        bitrate: Int,
        audioEnabled: Boolean,
    ) {
        try {
            cleanupHardware()

            val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val projection = mpm.getMediaProjection(resultCode, resultData)
            if (projection == null) {
                eventCallback?.invoke("error", "No se pudo obtener MediaProjection.")
                stopSelf()
                return
            }

            // Obligatorio en Android 14/15 antes de createVirtualDisplay
            projection.registerCallback(projectionCallback, mainHandler)
            mediaProjection = projection

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

            if (audioEnabled) {
                recorder.setAudioSource(MediaRecorder.AudioSource.MIC)
            }
            recorder.setVideoSource(MediaRecorder.VideoSource.SURFACE)
            recorder.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            recorder.setVideoEncoder(MediaRecorder.VideoEncoder.H264)
            if (audioEnabled) {
                recorder.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                recorder.setAudioEncodingBitRate(128_000)
                recorder.setAudioSamplingRate(44100)
            }
            recorder.setVideoEncodingBitRate(bitrate)
            recorder.setVideoFrameRate(30)
            recorder.setVideoSize(width, height)
            recorder.setOutputFile(cacheFile.absolutePath)
            recorder.prepare()

            val dpi = resources.displayMetrics.densityDpi
            virtualDisplay = projection.createVirtualDisplay(
                "NenoCamGalleryRecorder",
                width,
                height,
                dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                recorder.surface,
                null,
                null,
            )

            recorder.start()
            mediaRecorder = recorder
            isRecording = true
            eventCallback?.invoke("started", outputFileName)
        } catch (e: Exception) {
            isRecording = false
            cleanupHardware()
            eventCallback?.invoke("error", e.message ?: "Error al iniciar la grabación")
            stopSelf()
        }
    }

    private fun stopRecordingAndSaveToGallery() {
        if (!isRecording && tempOutputFile == null) {
            stopSelf()
            return
        }

        isRecording = false
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
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {
        }
        virtualDisplay = null

        try {
            mediaRecorder?.reset()
            mediaRecorder?.release()
        } catch (_: Exception) {
        }
        mediaRecorder = null

        try {
            mediaProjection?.unregisterCallback(projectionCallback)
            mediaProjection?.stop()
        } catch (_: Exception) {
        }
        mediaProjection = null
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
                description = "Grabación local de producción multicámara para Galería"
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
            .setContentText("Guardando producción en MP4 para tu Galería...")
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
