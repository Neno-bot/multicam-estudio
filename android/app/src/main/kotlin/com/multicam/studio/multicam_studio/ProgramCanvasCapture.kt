package com.multicam.studio.multicam_studio

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Rect
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.view.PixelCopy
import android.view.Surface
import android.view.View
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Captura EXCLUSIVAMENTE el rectángulo del Monitor EN VIVO (cuadro rojo)
 * directamente desde la ventana de NenoCam Studio usando PixelCopy.
 *
 * Ventajas clave:
 * - NO usa MediaProjection (nunca muestra el aviso "Compartir pantalla / una app").
 * - NUNCA captura notificaciones de WhatsApp, mensajes, barra de estado ni botones del Director.
 * - Escala el cuadro EN VIVO a 16:9 completo sin bordes negros.
 */
object ProgramCanvasCapture {

    @Volatile
    private var activityRef: WeakReference<Activity>? = null

    @Volatile
    private var cropLeft: Int = 0

    @Volatile
    private var cropTop: Int = 0

    @Volatile
    private var cropRight: Int = 0

    @Volatile
    private var cropBottom: Int = 0

    fun attachActivity(activity: Activity) {
        activityRef = WeakReference(activity)
    }

    fun detachActivity(activity: Activity) {
        if (activityRef?.get() === activity) {
            activityRef = null
        }
    }

    fun updateCropRect(left: Int, top: Int, right: Int, bottom: Int) {
        cropLeft = left
        cropTop = top
        cropRight = right
        cropBottom = bottom
    }

    fun getActivity(): Activity? = activityRef?.get()

    /**
     * Calcula el rectángulo exacto dentro de Activity.window (en píxeles físicos)
     * sumando el desplazamiento de la vista raíz (recorte de cámara / barra de estado).
     */
    fun computeWindowCropRect(activity: Activity): Rect? {
        val decor = activity.window?.decorView ?: return null
        val decorW = decor.width
        val decorH = decor.height
        if (decorW <= 0 || decorH <= 0) return null

        val contentView: View? = decor.findViewById(android.R.id.content)
        val loc = IntArray(2)
        contentView?.getLocationInWindow(loc)
        val offsetX = loc[0]
        val offsetY = loc[1]

        val rawL = cropLeft + offsetX
        val rawT = cropTop + offsetY
        val rawR = cropRight + offsetX
        val rawB = cropBottom + offsetY

        val l = rawL.coerceIn(0, decorW - 2)
        val t = rawT.coerceIn(0, decorH - 2)
        val r = rawR.coerceIn(l + 2, decorW)
        val b = rawB.coerceIn(t + 2, decorH)

        // Si aún no se reportó un rectángulo válido desde Flutter, usar la ventana completa
        if ((cropRight - cropLeft) < 32 || (cropBottom - cropTop) < 32) {
            return Rect(0, 0, decorW, decorH)
        }
        return Rect(l, t, r, b)
    }

    /**
     * Bomba de fotogramas dedicada que copia únicamente el cuadro EN VIVO
     * hacia una Surface de salida (MediaRecorder o RootEncoder SurfaceTexture).
     */
    class FramePump(
        private val targetSurface: Surface,
        private val outWidth: Int,
        private val outHeight: Int,
        private val fps: Int = 25,
    ) {
        private val running = AtomicBoolean(false)
        private val inFlight = AtomicBoolean(false)
        private var workerThread: HandlerThread? = null
        private var workerHandler: Handler? = null
        private var copyBitmap: Bitmap? = null
        private val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.DITHER_FLAG)
        private val destRect = Rect(0, 0, outWidth, outHeight)
        private val frameIntervalMs = (1000L / fps.coerceIn(10, 30)).coerceAtLeast(33L)

        private val tickRunnable = object : Runnable {
            override fun run() {
                if (!running.get()) return
                captureOnce()
                if (running.get()) {
                    workerHandler?.postDelayed(this, frameIntervalMs)
                }
            }
        }

        fun start() {
            if (running.getAndSet(true)) return
            val thread = HandlerThread("NenoCamProgramPump")
            thread.start()
            workerThread = thread
            workerHandler = Handler(thread.looper)
            workerHandler?.post(tickRunnable)
        }

        fun stop() {
            running.set(false)
            workerHandler?.removeCallbacksAndMessages(null)
            workerThread?.quitSafely()
            workerThread = null
            workerHandler = null
            try {
                copyBitmap?.recycle()
            } catch (_: Exception) {
            }
            copyBitmap = null
        }

        private fun captureOnce() {
            if (!running.get() || !targetSurface.isValid) return
            if (!inFlight.compareAndSet(false, true)) return

            val activity = getActivity()
            val window = activity?.window
            val handler = workerHandler
            if (activity == null || activity.isFinishing || activity.isDestroyed || window == null || handler == null) {
                inFlight.set(false)
                return
            }

            val rect = computeWindowCropRect(activity)
            if (rect == null || rect.width() < 16 || rect.height() < 16) {
                inFlight.set(false)
                return
            }

            val bmp = ensureBitmap(rect.width(), rect.height())

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                try {
                    PixelCopy.request(
                        window,
                        rect,
                        bmp,
                        { copyResult ->
                            try {
                                if (copyResult == PixelCopy.SUCCESS && running.get() && targetSurface.isValid) {
                                    drawBitmapToSurface(bmp)
                                }
                            } finally {
                                inFlight.set(false)
                            }
                        },
                        handler,
                    )
                } catch (_: Exception) {
                    inFlight.set(false)
                }
            } else {
                // Fallback para Android 7 o anterior
                try {
                    val view = window.decorView
                    val c = Canvas(bmp)
                    c.translate(-rect.left.toFloat(), -rect.top.toFloat())
                    view.draw(c)
                    if (running.get() && targetSurface.isValid) {
                        drawBitmapToSurface(bmp)
                    }
                } catch (_: Exception) {
                } finally {
                    inFlight.set(false)
                }
            }
        }

        private fun ensureBitmap(w: Int, h: Int): Bitmap {
            val current = copyBitmap
            if (current != null && !current.isRecycled && current.width == w && current.height == h) {
                return current
            }
            try {
                current?.recycle()
            } catch (_: Exception) {
            }
            val created = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            copyBitmap = created
            return created
        }

        private fun drawBitmapToSurface(src: Bitmap) {
            if (!targetSurface.isValid) return
            var canvas: Canvas? = null
            try {
                canvas = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    targetSurface.lockHardwareCanvas()
                } else {
                    targetSurface.lockCanvas(null)
                }
                if (canvas != null) {
                    canvas.drawColor(Color.BLACK)
                    canvas.drawBitmap(src, null, destRect, paint)
                }
            } catch (_: Exception) {
                try {
                    canvas = targetSurface.lockCanvas(null)
                    if (canvas != null) {
                        canvas.drawColor(Color.BLACK)
                        canvas.drawBitmap(src, null, destRect, paint)
                    }
                } catch (_: Exception) {
                    canvas = null
                }
            } finally {
                if (canvas != null) {
                    try {
                        targetSurface.unlockCanvasAndPost(canvas)
                    } catch (_: Exception) {
                    }
                }
            }
        }
    }
}
