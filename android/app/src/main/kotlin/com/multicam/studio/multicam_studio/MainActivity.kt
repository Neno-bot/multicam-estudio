package com.multicam.studio.multicam_studio

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val METHOD_CHANNEL = "com.nenocam.studio/rtmp"
        private const val EVENT_CHANNEL = "com.nenocam.studio/rtmp_events"
        private const val RECORDER_METHOD_CHANNEL = "com.nenocam.studio/recorder"
        private const val RECORDER_EVENT_CHANNEL = "com.nenocam.studio/recorder_events"
    }

    private var eventSink: EventChannel.EventSink? = null
    private var recorderEventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Usa FlutterTextureView para que PixelCopy capture el video real (cámaras, videos, capas)
    // sin quedar en negro por el agujero de SurfaceView.
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ProgramCanvasCapture.attachActivity(this)
    }

    override fun onResume() {
        super.onResume()
        ProgramCanvasCapture.attachActivity(this)
    }

    override fun onDestroy() {
        ProgramCanvasCapture.detachActivity(this)
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        ProgramCanvasCapture.attachActivity(this)

        // --- Canal de eventos y comandos RTMP (YouTube / Facebook Live — SOLO cuadro EN VIVO) ---
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
                    "updateCaptureRect" -> {
                        val left = call.argument<Int>("left") ?: 0
                        val top = call.argument<Int>("top") ?: 0
                        val right = call.argument<Int>("right") ?: 0
                        val bottom = call.argument<Int>("bottom") ?: 0
                        ProgramCanvasCapture.updateCropRect(left, top, right, bottom)
                        result.success(true)
                    }

                    "startStream" -> {
                        val url = call.argument<String>("url")
                        val bitrateKbps = call.argument<Int>("bitrateKbps") ?: 2500
                        val audioEnabled = call.argument<Boolean>("audioEnabled") ?: true

                        if (url.isNullOrBlank()) {
                            result.error("INVALID_URL", "Falta la URL o clave RTMP", null)
                            return@setMethodCallHandler
                        }

                        ProgramCanvasCapture.attachActivity(this)
                        val serviceIntent = Intent(this, RtmpStreamService::class.java).apply {
                            action = RtmpStreamService.ACTION_START
                            putExtra(RtmpStreamService.EXTRA_URL, url)
                            putExtra(RtmpStreamService.EXTRA_BITRATE, bitrateKbps * 1024)
                            putExtra(RtmpStreamService.EXTRA_AUDIO_ENABLED, audioEnabled)
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
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

        // --- Canal de eventos y comandos Grabación Local a Galería (MP4 — SOLO cuadro EN VIVO) ---
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDER_EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    recorderEventSink = events
                    ScreenRecordService.eventCallback = { eventType, message ->
                        mainHandler.post {
                            recorderEventSink?.success(
                                mapOf("event" to eventType, "message" to message)
                            )
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    recorderEventSink = null
                    ScreenRecordService.eventCallback = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RECORDER_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startRecording" -> {
                        val width = call.argument<Int>("width") ?: 1280
                        val height = call.argument<Int>("height") ?: 720
                        val bitrateKbps = call.argument<Int>("bitrateKbps") ?: 4000
                        val audioEnabled = call.argument<Boolean>("audioEnabled") ?: true

                        ProgramCanvasCapture.attachActivity(this)
                        val serviceIntent = Intent(this, ScreenRecordService::class.java).apply {
                            action = ScreenRecordService.ACTION_START
                            putExtra(ScreenRecordService.EXTRA_WIDTH, width)
                            putExtra(ScreenRecordService.EXTRA_HEIGHT, height)
                            putExtra(ScreenRecordService.EXTRA_BITRATE, bitrateKbps * 1000)
                            putExtra(ScreenRecordService.EXTRA_AUDIO_ENABLED, audioEnabled)
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(serviceIntent)
                        } else {
                            startService(serviceIntent)
                        }
                        result.success(true)
                    }

                    "stopRecording" -> {
                        val stopIntent = Intent(this, ScreenRecordService::class.java).apply {
                            action = ScreenRecordService.ACTION_STOP
                        }
                        startService(stopIntent)
                        result.success(true)
                    }

                    "isRecording" -> {
                        result.success(ScreenRecordService.isRecording)
                    }

                    else -> result.notImplemented()
                }
            }
    }
}
