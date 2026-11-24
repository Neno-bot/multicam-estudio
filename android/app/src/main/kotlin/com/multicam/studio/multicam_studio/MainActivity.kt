package com.multicam.studio.multicam_studio

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.nenocam.studio/rtmp"
        private const val EVENT_CHANNEL = "com.nenocam.studio/rtmp_events"
        private const val REQUEST_MEDIA_PROJECTION = 9101
    }

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var pendingUrl: String? = null
    private var pendingBitrate: Int = 2500 * 1024
    private var pendingAudioEnabled: Boolean = true
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    RtmpStreamService.eventCallback = { eventType, message ->
                        mainHandler.post {
                            eventSink?.success(
                                mapOf("event" to eventType, "message" to message)
                            )
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    RtmpStreamService.eventCallback = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startStream" -> {
                        val url = call.argument<String>("url")
                        val bitrateKbps = call.argument<Int>("bitrateKbps") ?: 2500
                        val audioEnabled = call.argument<Boolean>("audioEnabled") ?: true

                        if (url.isNullOrBlank()) {
                            result.error("INVALID_URL", "Falta la URL o clave RTMP", null)
                            return@setMethodCallHandler
                        }

                        pendingUrl = url
                        pendingBitrate = bitrateKbps * 1024
                        pendingAudioEnabled = audioEnabled
                        pendingResult = result

                        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                        @Suppress("DEPRECATION")
                        startActivityForResult(mpm.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
                    }

                    "stopStream" -> {
                        val stopIntent = Intent(this, RtmpStreamService::class.java).apply {
                            action = RtmpStreamService.ACTION_STOP
                        }
                        startService(stopIntent)
                        result.success(true)
                    }

                    "isStreaming" -> {
                        result.success(RtmpStreamService.isLiveStreaming)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            val callback = pendingResult
            pendingResult = null

            if (resultCode == Activity.RESULT_OK && data != null && pendingUrl != null) {
                val serviceIntent = Intent(this, RtmpStreamService::class.java).apply {
                    action = RtmpStreamService.ACTION_START
                    putExtra(RtmpStreamService.EXTRA_URL, pendingUrl)
                    putExtra(RtmpStreamService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(RtmpStreamService.EXTRA_RESULT_DATA, data)
                    putExtra(RtmpStreamService.EXTRA_BITRATE, pendingBitrate)
                    putExtra(RtmpStreamService.EXTRA_AUDIO_ENABLED, pendingAudioEnabled)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    startForegroundService(serviceIntent)
                } else {
                    startService(serviceIntent)
                }
                callback?.success(true)
            } else {
                callback?.error("CANCELLED", "Permiso de captura de pantalla cancelado por el usuario.", null)
            }
        }
    }
}
