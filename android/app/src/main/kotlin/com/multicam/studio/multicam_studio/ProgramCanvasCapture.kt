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
import android.os.Looper
import android.view.PixelCopy
import android.view.Surface
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import java.lang.ref.WeakReference
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Captura EXCLUSIVAMENTE el rectángulo del Monitor EN VIVO (cuadro rojo)
 * desde FlutterTextureView / Activity.window sin usar MediaProjection.
 *
 * - Cero aviso "Compartir pantalla / una app".
 * - Cero notificaciones de WhatsApp, mensajes, barra de estado ni botones del Director.
 * - Escribe cuadros RGBA vía lockCanvas(null) en la SurfaceTexture de RootEncoder (OpenGL ES)
 *   para máxima compatibilidad en Samsung Exynos, Snapdragon y MediaTek.
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

    fun findTextureView(root: View?): TextureView? {
        if (root == null) return null
        if (root is TextureView && root.isAvailable) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                val found = findTextureView(root.getChildAt(i))
                if (found != null) return found
            }
        }
        return null
    }

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

        if ((cropRight - cropLeft) < 32 || (cropBottom - cropTop) < 32) {
            return Rect(0, 0, decorW, decorH)
        }

        val l = (cropLeft + offsetX).coerceIn(0, decorW - 2)
        val t = (cropTop + offsetY).coerceIn(0, decorH - 2)
        val r = (cropRight + offsetX).coerceIn(l + 2, decorW)
        val b = (cropBottom + offsetY).coerceIn(t + 2, decorH)
        return Rect(l, t, r, b)
    }

    /**
     * Bomba de fotogramas que entrega cuadros del cuadro EN VIVO a RootEncoder (SurfaceTexture).
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
        private val mainHandler = Handler(Looper.getMainLooper())
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

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val bmp = ensureBitmap(rect.width(), rect.height())
                try {
                    PixelCopy.request(
                        window,
                        rect,
                        bmp,
                        { copyResult ->
                            try {
                                if (copyResult == PixelCopy.SUCCESS && running.get() && targetSurface.isValid) {
                                    drawBitmapToSurface(bmp, null)
                                } else if (running.get() && targetSurface.isValid) {
                                    captureFromTextureViewFallback(activity, rect)
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
                captureFromTextureViewFallback(activity, rect)
                inFlight.set(false)
            }
        }

        private fun captureFromTextureViewFallback(activity: Activity, windowRect: Rect) {
            mainHandler.post {
                if (!running.get() || !targetSurface.isValid) return@post
                try {
                    val tv = findTextureView(activity.window?.decorView) ?: return@post
                    val fullBmp = tv.bitmap ?: return@post
                    val loc = IntArray(2)
                    tv.getLocationInWindow(loc)
                    val srcL = (windowRect.left - loc[0]).coerceIn(0, fullBmp.width - 2)
                    val srcT = (windowRect.top - loc[1]).coerceIn(0, fullBmp.height - 2)
                    val srcR = (windowRect.right - loc[0]).coerceIn(srcL + 2, fullBmp.width)
                    val srcB = (windowRect.bottom - loc[1]).coerceIn(srcT + 2, fullBmp.height)
                    val srcRect = Rect(srcL, srcT, srcR, srcB)
                    workerHandler?.post {
                        try {
                            if (running.get() && targetSurface.isValid) {
                                drawBitmapToSurface(fullBmp, srcRect)
                            }
                        } finally {
                            try {
                                fullBmp.recycle()
                            } catch (_: Exception) {
                            }
                        }
                    }
                } catch (_: Exception) {
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

        /**
         * Usa lockCanvas(null) (software BufferQueue RGBA) directamente sobre Surface(surfaceTexture),
         * lo cual dispara onFrameAvailable() en el pipeline OpenGL ES de RootEncoder sin generar cuadros negros.
         */
        private fun drawBitmapToSurface(src: Bitmap, srcRect: Rect?) {
            if (!targetSurface.isValid || src.isRecycled) return
            var canvas: Canvas? = null
            try {
                canvas = targetSurface.lockCanvas(null)
                if (canvas != null) {
                    canvas.drawColor(Color.BLACK)
                    canvas.drawBitmap(src, srcRect, destRect, paint)
                }
            } catch (_: Exception) {
                canvas = null
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
