package com.multicam.studio.multicam_studio

import android.graphics.SurfaceTexture
import android.view.Surface
import com.pedro.encoder.input.sources.OrientationForced
import com.pedro.encoder.input.sources.video.VideoSource

/**
 * Fuente de video personalizada para RootEncoder (GenericStream) que alimenta
 * únicamente el Monitor EN VIVO (cuadro rojo) sin usar MediaProjection ni capturar notificaciones.
 */
class ProgramCanvasVideoSource : VideoSource() {

    private var running = false
    private var surface: Surface? = null
    private var pump: ProgramCanvasCapture.FramePump? = null

    override fun create(width: Int, height: Int, fps: Int, rotation: Int): Boolean {
        return true
    }

    override fun start(surfaceTexture: SurfaceTexture) {
        this.surfaceTexture = surfaceTexture
        val w = if (width > 0) width else 1280
        val h = if (height > 0) height else 720
        val targetFps = if (fps > 0) fps else 25

        surfaceTexture.setDefaultBufferSize(w, h)
        val outSurface = Surface(surfaceTexture)
        surface = outSurface

        val framePump = ProgramCanvasCapture.FramePump(
            targetSurface = outSurface,
            outWidth = w,
            outHeight = h,
            fps = targetFps,
        )
        pump = framePump
        running = true
        framePump.start()
    }

    override fun stop() {
        running = false
        pump?.stop()
        pump = null
        try {
            surface?.release()
        } catch (_: Exception) {
        }
        surface = null
        surfaceTexture = null
    }

    override fun release() {
        stop()
    }

    override fun isRunning(): Boolean = running

    // Evita que RootEncoder aplique la rotación de 270° pensada para sensores de cámara vertical;
    // fuerza orientación horizontal pura (0°) en grabación MP4 y transmisión RTMP.
    override fun getOrientationConfig(): OrientationForced = OrientationForced.LANDSCAPE
}
